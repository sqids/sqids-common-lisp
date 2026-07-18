# cl-sqids 使用说明

> 本文档是 cl-sqids 的实战指南。如果只看 API 签名请参考 [README.md](./README.md)。
>
> This is a hands-on guide for cl-sqids. For the API reference see [README.md](./README.md).

## 目录

- [1. 准备](#1-准备)
- [2. 30 秒上手](#2-30-秒上手)
- [3. 核心概念](#3-核心概念)
- [4. 常见场景](#4-常见场景)
- [5. 自定义配置详解](#5-自定义配置详解)
- [6. 错误处理](#6-错误处理)
- [7. 与其他语言端口互操作](#7-与其他语言端口互操作)
- [8. 性能与内存](#8-性能与内存)
- [9. 最佳实践](#9-最佳实践)
- [10. 常见陷阱 FAQ](#10-常见陷阱-faq)
- [English Quick Reference](#english-quick-reference)

---

## 1. 准备

### 1.1 环境

| 实现 | 最低版本 |
|---|---|
| SBCL | 2.6.6 及更新 |
| CCL (Clozure CL) | 1.13 及更新 |

依赖：**只有 FiveAM（仅测试用）**。核心库零外部依赖。

### 1.2 安装

**Quicklisp（推荐）：**

```bash
cd ~/quicklisp/local-projects/
git clone https://github.com/TTalkPro/cl-sqids.git
```

```lisp
(ql:quickload :cl-sqids)
; => (:CL-SQIDS)
```

**ASDF：**

```lisp
(require :asdf)
(pushnew #P"/path/to/cl-sqids/" asdf:*central-registry* :test #'equal)
(asdf:load-system :cl-sqids)
```

### 1.3 包导入

cl-sqids 导出的所有公共符号都在 `#:cl-sqids` 包里。推荐使用完整包前缀（让代码更易搜索）：

```lisp
(defpackage #:my-app
  (:use #:common-lisp))
(in-package #:my-app)

(cl-sqids:make-sqids)
```

如果你嫌弃前缀太长，可以使用包局部昵称（SBCL/CCL 均支持）：

```lisp
(defpackage #:my-app
  (:use #:common-lisp)
  (:local-nicknames (#:sqids #:cl-sqids)))
(in-package #:my-app)

(sqids:make-sqids)        ; 等价于 cl-sqids:make-sqids
(sqids:encode '(1 2 3) *) ; 两个符号都对
```

---

## 2. 30 秒上手

```lisp
(ql:quickload :cl-sqids)

(defparameter *s* (cl-sqids:make-sqids))

(cl-sqids:encode '(1 2 3) *s*)  ; => "86Rf07"
(cl-sqids:decode "86Rf07" *s*)  ; => (1 2 3)
```

就这么简单。`make-sqids` 不带参数即用默认配置（62 字符字母表、内置 210 词黑名单）。

---

## 3. 核心概念

### 3.1 什么是 sqids

sqids 是一组**非负整数**与**短字符串**之间的双向映射：

| 输入 | 输出 |
|---|---|
| `(1 2 3)` | `"86Rf07"` |
| `(4572721)` | `"JExTR"` |
| `(0)` | `"bM"` |
| `()` | `""` |

它**不是** 加密算法、不是哈希函数、也不是 UUID。它的用途是：把"内部一串数字"变成"对外可分享的短 ID"。

### 3.2 关键特性

- **确定性**：相同输入永远产生相同输出（同一实例下）
- **可逆**：解码即得原始数字
- **屏蔽脏话**：内置黑名单自动避开 `"fuck"`、`"shit"` 等
- **可定制**：字母表、最小长度、黑名单都可配置

### 3.3 实例是不可变的

```lisp
(defparameter *s* (cl-sqids:make-sqids))

(setf (cl-sqids:alphabet *s*) "abc") 
;; => 错误：ALPHABET 是 :reader，没有 setf 方法
```

要换配置？构造一个新实例：

```lisp
(defparameter *s2* (cl-sqids:make-sqids :alphabet "abc..."))
```

这是 [Google CL Style Guide](https://google.github.io/styleguide/lispguide.xml) 的设计取向：避免 `:accessor` + 手动重写 setf 的反模式。

### 3.4 字母表在构造时被洗牌一次

```lisp
(cl-sqids:alphabet (cl-sqids:make-sqids))
;; => "vU7Kbj2pJWcRw9XYgT5Nq8aP3dhLZiFkrVCStzAHMxIef0yoQ46EG1nDBuOsm" 
;;    （类似乱序字符串，每次安装都一样）
```

洗牌是**确定性的**（基于字符 code point 与索引计算，不含随机数）。
所以你重装 cl-sqids、换机器，默认实例的 `(alphabet s)` 永远是这一串。

---

## 4. 常见场景

### 4.1 数据库主键 → 可分享 ID

把内部自增 ID（如 Postgres `BIGSERIAL`）转成不暴露业务体量的对外 ID：

```lisp
(defparameter *id-sqids* (cl-sqids:make-sqids :min-length 10))

(defun public-id (db-id)
  "数据库主键 → 10 字符对外 ID。"
  (cl-sqids:encode (list db-id) *id-sqids*))

(defun lookup-by-public-id (public-id)
  "对外 ID → 数据库主键。"
  (let ((nums (cl-sqids:decode public-id *id-sqids*)))
    (when (and nums (= 1 (length nums)))
      (first nums))))

(public-id 1)            ; => "UKgmr6HJOd"
(public-id 999999)       ; => "wYQEaD9WZk"
(lookup-by-public-id "UKgmr6HJOd") ; => 1
```

> **注意**：sqids **不提供加密强度**。任何人都可解码出原始 ID。
> 如果你要"防猜测"请在外层加 HMAC 或 AES。

### 4.2 复合主键（多字段）

把 `(user_id, post_id, reply_id)` 这种复合主键压成一个字符串：

```lisp
(defparameter *route-sqids* (cl-sqids:make-sqids))

(defun make-route (user post reply)
  (cl-sqids:encode (list user post reply) *route-sqids*))

(defun parse-route (route)
  (let ((nums (cl-sqids:decode route *route-sqids*)))
    (if (= 3 (length nums))
        (values-list nums)
        (error "非法路由"))))

(make-route 42 1234 5678)        ; => "..."
(multiple-value-bind (u p r) (parse-route "...")
  (list u p r))                  ; => (42 1234 5678)
```

URL 风格：`https://example.com/p/<route>`。

### 4.3 邀请码 / 分享码（带最小长度）

```lisp
(defparameter *invite-sqids* 
  (cl-sqids:make-sqids :min-length 8))

(cl-sqids:encode (list 12345) *invite-sqids*) ; => 至少 8 字符
```

### 4.4 自定义字母表（无歧义字符）

避免 `0/O`、`1/l/I` 这类视觉歧义字符，便于口头转述或手抄：

```lisp
(defparameter *readable-sqids*
  (cl-sqids:make-sqids 
    :alphabet "abcdefghijkmnpqrstuvwxyz23456789")) ; 去掉 0/o/1/l/i
```

### 4.5 关闭黑名单（性能优先）

如果你的 ID 不会被人类看到（如内部 token、机器对机器通信），关掉黑名单省一次重排：

```lisp
(defparameter *fast-sqids*
  (cl-sqids:make-sqids :blocklist '()))
```

### 4.6 多个实例共存

不同业务用不同配置，互不干扰：

```lisp
(defparameter *user-ids* (cl-sqids:make-sqids :min-length 8))
(defparameter *order-ids* (cl-sqids:make-sqids :min-length 12 :alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
(defparameter *share-codes* (cl-sqids:make-sqids :min-length 6 :blocklist '()))
```

---

## 5. 自定义配置详解

### 5.1 字母表（:alphabet）

约束：

| 规则 | 说明 |
|---|---|
| 长度 ≥ 3 | 否则抛 `alphabet-too-short-error` |
| 字符唯一 | 否则抛 `alphabet-duplicates-error` |
| 仅 ASCII（code ≤ 127） | 否则抛 `alphabet-multibyte-error` |

```lisp
(cl-sqids:make-sqids :alphabet "0123456789abcdef")     ; ✓ hex
(cl-sqids:make-sqids :alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ") ; ✓ 26 大写
(cl-sqids:make-sqids :alphabet "abc")                  ; ✓ 最少 3 字符
(cl-sqids:make-sqids :alphabet "ab")                   ; ✗ 太短
(cl-sqids:make-sqids :alphabet "aabbc")                ; ✗ 有重复
(cl-sqids:make-sqids :alphabet "éabc")                 ; ✗ 非 ASCII
```

**字母表越短 → 输出越长。** 62 字符（默认）下 `(1 2 3)` 是 6 字符；用 `"abc"` 时会变长很多。

### 5.2 最小长度（:min-length）

| 约束 | 说明 |
|---|---|
| 类型 | 整数 |
| 范围 | `[0, 255]` 闭区间 |
| 默认 | `0`（不加填充）|

```lisp
(let ((s (cl-sqids:make-sqids)))
  (cl-sqids:encode '(1 2 3) s))            ; => "86Rf07" （6 字符）

(let ((s (cl-sqids:make-sqids :min-length 10)))
  (cl-sqids:encode '(1 2 3) s))            ; => "86Rf07xd4z" （10 字符）

(let ((s (cl-sqids:make-sqids :min-length 62)))
  (cl-sqids:encode '(1 2 3) s))            ; => "86Rf07xd4zBmiJXQG6otHEbew02c3PWsUOLZxADhCpKj7aVFv9I8RquYrNlSTM"
```

填充算法：在自然编码后追加一个分隔符，然后反复 shuffle 字母表并取片段。解码器遇到两个相邻分隔符即识别为填充并停止。

### 5.3 黑名单（:blocklist）

#### 三级匹配规则（与官方规范完全一致）

设 ID 长度为 `n`，黑名单词长度为 `m`：

| 条件 | 匹配方式 |
|---|---|
| `n ≤ 3` **或** `m = 3` | 精确相等（`id == word`）|
| `n > 3` **且** 词包含数字 | 前缀或后缀匹配 |
| `n > 3` **且** 词不含数字 | 子串匹配 |

匹配**大小写不敏感**。构造时会**预过滤**：

- 丢弃 `m < 3` 的词
- 丢弃包含字母表外字符的词

```lisp
(cl-sqids:make-sqids :blocklist '("foo" "bar" "DEAD"))    ; ✓
(cl-sqids:make-sqids :blocklist '("a"))                   ; "a" 太短，被丢弃
(cl-sqids:make-sqids :blocklist '("xyz" "ABC") 
                     :alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
; "xyz" 含字母表外字符，被丢弃；只保留 "ABC"
```

#### 关闭黑名单

```lisp
(cl-sqids:make-sqids :blocklist '())   ; 空列表
;; 或用 nil
(cl-sqids:make-sqids :blocklist nil)
```

#### 验证某个 ID 是否被屏蔽

构造时已经把黑名单分为 3 个内部列表，可以直接调内部 API（但建议用 round-trip 测试间接验证）：

```lisp
(let ((s (cl-sqids:make-sqids)))
  (cl-sqids:encode '(4572721) s))  ; => "JExTR" （而不是 "aho1e"，因为被屏蔽）

(let ((s (cl-sqids:make-sqids :blocklist '())))
  (cl-sqids:encode '(4572721) s))  ; => "aho1e"
```

---

## 6. 错误处理

### 6.1 条件类型一览

```
sqids-error                            ; 所有 cl-sqids 错误的基类
├── alphabet-error                     ; 字母表相关错误的基类
│   ├── alphabet-too-short-error       ; 字母表 < 3 字符
│   ├── alphabet-duplicates-error      ; 字母表有重复字符
│   └── alphabet-multibyte-error       ; 字母表含非 ASCII 字符
├── min-length-out-of-range-error      ; min-length 不在 [0, 255]
├── max-regenerate-attempts-error      ; 黑名单导致无法生成
└── unsupported-numbers-type-error     ; encode 输入非法
```

### 6.2 推荐用法：捕获整个家族

```lisp
(handler-case
    (cl-sqids:make-sqids :alphabet (user-input))
  (cl-sqids:sqids-error (c)
    ;; 一个分支捕获所有 cl-sqids 抛出的错误
    (log:error "sqids 配置错误: ~A" c)
    (give-up)))
```

### 6.3 精细化处理

```lisp
(handler-case
    (let ((s (cl-sqids:make-sqids :alphabet raw)))
      (cl-sqids:encode numbers s))
  (cl-sqids:alphabet-too-short-error (c)
    (format nil "字母表至少 3 个字符，当前: ~A" (cl-sqids:alphabet c)))
  (cl-sqids:alphabet-duplicates-error (c)
    (format nil "字母表不能有重复字符: ~A" (cl-sqids:alphabet c)))
  (cl-sqids:alphabet-multibyte-error (c)
    (format nil "字母表不能含非 ASCII 字符: ~A" (cl-sqids:condition-char c)))
  (cl-sqids:unsupported-numbers-type-error (c)
    (format nil "编码输入必须是非负整数或其列表: ~A" (cl-sqids:condition-value c)))
  (cl-sqids:max-regenerate-attempts-error ()
    "黑名单太严格，无法生成合规 ID"))
```

### 6.4 关键细节

- `alphabet-error` 子类的实例可以通过 `(alphabet c)` 读取到出错的字母表
- `alphabet-multibyte-error` 还有 `(condition-char c)` 拿到具体的非 ASCII 字符
- `unsupported-numbers-type-error` / `min-length-out-of-range-error` 有 `(condition-value c)`
- 所有条件都有自定义 `:report`，直接 `princ` 即有人类可读信息：

```lisp
(let ((c (make-condition 'cl-sqids:alphabet-too-short-error :alphabet "ab")))
  (princ c))
;; => "Alphabet length must be at least 3 (got 2 characters)."
```

---

## 7. 与其他语言端口互操作

cl-sqids 与 [sqids-python](https://github.com/sqids/sqids-python)、[sqids-js](https://github.com/sqids/sqids-js)、[sqids-go](https://github.com/sqids/sqids-go) 等所有官方端口**字节级兼容**。

### 7.1 共享 ID（跨语言编解码）

```python
# Python 端
from sqids import Sqids
s = Sqids()
id = s.encode([1, 2, 3])  # => "86Rf07"
```

```lisp
;; Common Lisp 端
(cl-sqids:decode "86Rf07" (cl-sqids:make-sqids)) ; => (1 2 3)
```

### 7.2 共享配置（关键）

必须用**相同的初始字母表**（默认对默认）才能互操作。因为字母表在构造时会被洗牌，且**洗牌是确定性的**，所以只要两边的初始字母表一致，洗牌结果就一致。

```python
# Python
s = Sqids(min_length=10)
s.encode([1, 2, 3])  # => "86Rf07xd4z"
```

```lisp
;; CL
(cl-sqids:encode '(1 2 3) (cl-sqids:make-sqids :min-length 10))
;; => "86Rf07xd4z"
```

### 7.3 黑名单也兼容

只要用相同的 `blocklist`（顺序无所谓，但内容要一致），跨语言端口产生的 ID 也一致：

```python
s = Sqids(blocklist=["foo", "bar"])
```

```lisp
(cl-sqids:make-sqids :blocklist '("foo" "bar"))
```

### 7.4 注意：默认 min-length 不同

- **官方默认 `min_length = 0`**（与 sqids-python / sqids-js 一致）
- cl-sqids 也用 0 作为默认值（早期版本曾用 6，已纠正）

如果你想恢复旧行为：`(make-sqids :min-length 6)`。

---

## 8. 性能与内存

### 8.1 典型耗时（SBCL 2.6.6, Linux x64）

大致数量级（你的实测数字会因硬件而异）：

| 操作 | 单次耗时 |
|---|---|
| `(make-sqids)` 含黑名单预过滤 | ~1 ms（一次性，启动时）|
| `(encode '(1 2 3) s)` | ~20 µs |
| `(decode "86Rf07" s)` | ~15 µs |
| `(encode '(1 2 3) s)` 关黑名单 | ~5 µs |

### 8.2 提速建议

1. **复用实例**。`make-sqids` 不便宜（要洗牌、过滤黑名单）。每次请求都新建实例是常见性能陷阱。

   ```lisp
   ;; ✗ 不要这样
   (defun encode-id (n)
     (cl-sqids:encode (list n) (cl-sqids:make-sqids)))
   
   ;; ✓ 这样才对
   (defparameter *s* (cl-sqids:make-sqids))
   (defun encode-id (n)
     (cl-sqids:encode (list n) *s*))
   ```

2. **关黑名单**（如确认 ID 不对人类可见）。

3. **声明类型**。如果你在热路径调用，把 `*s*` 声明为 `sqids` 类型可帮助 SBCL 优化：

   ```lisp
   (defun encode-id (n)
     (declare (type (integer 0) n)
              (optimize (speed 3) (safety 1)))
     (let ((s (load-time-value (cl-sqids:make-sqids))))
       (cl-sqids:encode (list n) s)))
   ```

### 8.3 内存

- 每个 `sqids` 实例约 5 KB（字母表 62 字符 + 三级黑名单 ~200 词）
- `encode` / `decode` 内部会复制字母表，不修改实例
- 无全局可变状态、无线程本地缓存（线程安全）

---

## 9. 最佳实践

### 9.1 ✅ 推荐

- **实例复用**：每个业务一个 `defparameter` 实例
- **类型注解**：热路径上加 `(optimize (speed 3))`
- **错误统一处理**：用 `handler-case` 捕获 `sqids-error` 基类
- **包局部昵称**：长项目里用 `:local-nicknames` 缩短前缀
- **配置放配置文件**：字母表、min-length、黑名单都应可配置化，不要硬编码

### 9.2 ❌ 避免

- **存储生成的 ID 时不要丢掉原数字**。sqids 是双向可逆，但解码可能失败（用户篡改 ID）。永远把原始数字存数据库，用 sqids 仅做展示。
- **不要把 sqids 当加密用**。任何人都能解码。需要保密就外层加 HMAC/AES。
- **不要假设黑名单涵盖所有敏感词**。它是基础过滤，不保证 100% 干净。
- **不要并发依赖内部状态**。虽然实例本身不可变，但若你自己在实例外维护状态，记得加锁。
- **不要混合不同实例编解码**。`encode` 用 A、`decode` 用 B 会出错。

---

## 10. 常见陷阱 FAQ

### Q1：`(encode 5 s)` 和 `(encode '(5) s)` 等价吗？

等价。`encode` 的方法对单个整数会自动 wrap 成 list：
```lisp
(cl-sqids:encode 5 s)      ; => "uw"
(cl-sqids:encode '(5) s)   ; => "uw"
```

### Q2：为什么 `(encode '(0) s)` 不是空字符串？

sqids 规范要求 `to-id` 用 `do/while` 语义：即便数字是 0，也至少产生一个字符。
所以 `(encode '(0) s)` 是 `"bM"`（一个字符的 ID + 一个分隔符）。

### Q3：为什么 `(decode "*" s)` 返回 `nil`？

`*` 不在默认字母表里。规范规定：解码时遇到字母表外字符，**返回空列表**，不报错。
这避免了让历史 / 错误 ID 触发异常。

### Q4：怎么生成多个不同 ID？

每次调 `encode` 同一数字 → 永远同结果（确定性）。要"不同 ID"，得改输入或改实例。

### Q5：能否生成不可解码的 ID？

不能。**所有 sqid 都可被解码**。要不可解码就别用 sqids，用 HMAC 之类的。

### Q6：构造时报 `alphabet-duplicates-error`，但我肉眼看没有重复？

很可能是字符串里有**不可见字符**（如空格、TAB、零宽空格 U+200B）。
用 `(length alphabet)` 看字符数，用 `(coerce alphabet 'list)` 逐字符检查。

### Q7：实例可以共享给多个线程吗？

可以。实例是不可变的，没有可变状态。多线程并发 encode/decode 安全。

### Q8：能否让 ID 看起来更"随机"？

sqids 不带随机性。但你可以：
- 缩短字母表（让 ID 更长更"乱"）
- 加 `:min-length`
- 输出后再做字符置换（但要确保双向一致）

### Q9：CCL 上跑得比 SBCL 慢？

正常。SBCL 在内层循环有更多优化。如果你用 CCL 且关心性能：
- 关黑名单
- 复用实例
- 编译时声明类型

### Q10：解码历史 ID 会失败吗？

不会，只要字母表和实例不变。规范要求解码器**不重新校验黑名单**——
过去生成的 ID 即使现在被新黑名单屏蔽，依然能正常解码。

---

## English Quick Reference

### Create instance

```lisp
(defparameter *s* (cl-sqids:make-sqids))                      ; defaults
(defparameter *s* (cl-sqids:make-sqids :min-length 10))       ; force 10+ chars
(defparameter *s* (cl-sqids:make-sqids :alphabet "abc..."))
(defparameter *s* (cl-sqids:make-sqids :blocklist '()))       ; disable blocklist
```

### Encode / decode

```lisp
(cl-sqids:encode '(1 2 3) *s*)  ; => "86Rf07"
(cl-sqids:encode 5 *s*)         ; => "uw"  (single integer OK)
(cl-sqids:encode '() *s*)       ; => ""
(cl-sqids:decode "86Rf07" *s*)  ; => (1 2 3)
(cl-sqids:decode "" *s*)        ; => NIL
(cl-sqids:decode "*" *s*)       ; => NIL  (invalid char)
```

### Common patterns

```lisp
;; Database primary key → public ID
(defun public-id (id)
  (cl-sqids:encode (list id) *id-sqids*))

;; Public ID → database primary key (with error handling)
(defun lookup (public-id)
  (let ((nums (cl-sqids:decode public-id *id-sqids*)))
    (unless (and nums (= 1 (length nums)))
      (error "Invalid public id"))
    (first nums)))

;; Compound key
(cl-sqids:encode (list user-id post-id reply-id) *route-sqids*)
```

### Error handling

```lisp
(handler-case
    (cl-sqids:make-sqids :alphabet raw-alphabet)
  (cl-sqids:alphabet-error (c)
    (log:error "Bad alphabet: ~A" (cl-sqids:alphabet c)))
  (cl-sqids:min-length-out-of-range-error ()
    (log:error "min-length must be in [0, 255]")))
```

### Cross-language compatibility

cl-sqids produces byte-identical output to [sqids-python](https://github.com/sqids/sqids-python) /
[sqids-js](https://github.com/sqids/sqids-js) /
[sqids-go](https://github.com/sqids/sqids-go) when given the same `:alphabet`,
`:min-length`, and `:blocklist`. Default settings interoperate with default settings
across all official ports.

### Performance tips

1. **Reuse instances** — `make-sqids` is not cheap (it shuffles the alphabet and filters the blocklist once).
2. **Disable the blocklist** if the IDs are never human-visible.
3. **Declare types** on hot paths: `(declare (type (integer 0) n))` lets SBCL optimize.

### Do not

- Do **not** store sqids as the primary storage — always keep the original integers in your DB.
- Do **not** treat sqids as encryption — they are reversible by anyone.
- Do **not** assume the blocklist catches every bad word — it is a baseline filter only.
- Do **not** interleave `encode` on instance A with `decode` on instance B.

### FAQ (short version)

| Q | A |
|---|---|
| Empty input? | `(encode '() s)` returns `""` |
| Decode unknown char? | Returns `NIL` (per spec) |
| Encode 0? | Single-char result (`"bM"`) — `to-id` uses `do/while` |
| Thread-safe? | Yes — instances are immutable |
| Encrypted? | **No** — anyone can decode |

---

## 反馈 / Feedback

发现问题或想补充文档？欢迎提 issue：
<https://github.com/TTalkPro/cl-sqids/issues>

代码贡献请先阅读 [TASK.md](./TASK.md) 了解项目当前状态。
