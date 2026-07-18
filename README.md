# cl-sqids

**中文** · [English](./README.en.md)

[![Common Lisp](https://img.shields.io/badge/Common%20Lisp-SBCL%20%7C%20CCL-success.svg)](https://common-lisp.dev/)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](./LICENSE)
[![Tests](https://img.shields.io/badge/tests-281%20checks%20%E2%9C%93-brightgreen.svg)](#运行测试)

> **cl-sqids** 是 [sqids](https://sqids.org/) 的 Common Lisp 实现。
> 把非负整数数组编码成短小、唯一、URL 安全、可逆的字符串 ID。

sqids（"squids"）是 hashids 的现代继任者：给定一组数字，生成一段短字符串；
再次解码即可还原原始数字。生成的 ID 会自动屏蔽黑名单中的脏话，保证可读性。

---

## 目录

- [特性](#特性)
- [安装](#安装)
- [快速开始](#快速开始)
- [API 参考](#api-参考)
- [自定义](#自定义)
- [错误条件](#错误条件)
- [运行测试](#运行测试)
- [兼容性](#兼容性)
- [项目结构](#项目结构)
- [许可证](#许可证)

> 📖 **完整的实战教程、常见场景、最佳实践与 FAQ 请见 [USAGE.md](./USAGE.md)。**
> 本 README 只列 API 参考；想看真实用法、性能建议、跨语言互操作等请读 USAGE.md。

---

## 特性

- 完整实现 [sqids 官方规范](https://github.com/sqids/sqids-spec)，与 Python / JavaScript / Go 等语言端口**结果一致**
- 基于 **CLOS** 的不可变 `sqids` 类
- 遵循 [Google Common Lisp 风格指南](https://google.github.io/styleguide/lispguide.xml)
- 同时支持 **SBCL** 与 **CCL** 两大主流 Common Lisp 实现
- 提供 **281 个单元测试**（FiveAM），与官方测试向量 1:1 对齐
- 通过宏（`with-peeled-separator`）与公共辅助函数消除重复代码
- 内置默认黑名单（约 210 个英文 / 多语言敏感词及 leet 变体）

---

## 安装

### 方式一：Quicklisp（推荐）

把本仓库克隆到 Quicklisp 的 `local-projects` 目录：

```bash
cd ~/quicklisp/local-projects/
git clone https://github.com/TTalkPro/cl-sqids.git
```

然后加载：

```lisp
(ql:quickload :cl-sqids)
```

### 方式二：ASDF

```bash
git clone https://github.com/TTalkPro/cl-sqids.git ~/workspace/cl-sqids
```

```lisp
(require :asdf)
(pushnew #P"/path/to/cl-sqids/" asdf:*central-registry* :test #'equal)
(asdf:load-system :cl-sqids)
```

---

## 快速开始

```lisp
(require :cl-sqids)

;; 创建一个默认的 sqids 实例
(defparameter *s* (cl-sqids:make-sqids))

;; 编码：一组数字 -> 短字符串
(cl-sqids:encode '(1 2 3) *s*)
;; => "86Rf07"

;; 也可以直接传单个整数
(cl-sqids:encode 1 *s*)
;; => "Uk"

;; 解码：字符串 -> 原始数字列表
(cl-sqids:decode "86Rf07" *s*)
;; => (1 2 3)
```

---

## API 参考

### `make-sqids` (&key alphabet min-length blocklist) → `sqids`

构造一个不可变的 `sqids` 编解码器。

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `:alphabet` | `string` | `*default-alphabet*` | 至少 3 个唯一 ASCII 字符 |
| `:min-length` | `(integer 0 255)` | `+default-min-length+` (0) | 生成 ID 的最小长度 |
| `:blocklist` | `list` | `*default-blocklist*` | 屏蔽词列表（区分大小写不敏感） |

构造时会**对字母表进行一次性洗牌并缓存**，与官方规范一致。
参数非法时分别抛出 `alphabet-error` 或 `min-length-out-of-range-error`。

### `encode` (numbers sqids) → `string`

把 `numbers` 编码为 sqid 字符串。

- `numbers` 可以是单个非负整数，或非负整数列表
- 空列表 → 空字符串 `""`
- 若生成的 ID 命中黑名单，会自动重排直至得到合规 ID
- 超过 `(+ (length alphabet) 1)` 次仍无法避开黑名单时，
  抛出 `max-regenerate-attempts-error`

### `decode` (id sqids) → `list`

把 sqid 字符串 `id` 解码为数字列表。

- 空字符串或包含字母表外字符的 ID → 返回 `nil`
- **不会**重新校验黑名单：旧 ID / 历史上被屏蔽过的 ID 仍可正常解码

### 公共读取器（只读）

| 函数 | 返回 |
|------|------|
| `(alphabet s)` | 实例已洗牌后的字母表（`simple-string`） |
| `(min-length s)` | 最小长度（`(integer 0 255)`） |
| `(blocklist-original s)` | 构造时传入的原始黑名单列表 |

---

## 自定义

### 自定义字母表

```lisp
(defparameter *hex-sqids*
  (cl-sqids:make-sqids :alphabet "0123456789abcdef"))

(cl-sqids:encode '(1 2 3) *hex-sqids*)
;; => "489158"
```

### 自定义最小长度

```lisp
(defparameter *s* (cl-sqids:make-sqids :min-length 10))
(cl-sqids:encode '(1 2 3) *s*)
;; => "86Rf07xd4z"
```

### 关闭黑名单

```lisp
(defparameter *raw* (cl-sqids:make-sqids :blocklist '()))
(cl-sqids:encode '(4572721) *raw*)
;; => "aho1e"  （默认会变成 "JExTR" 因为 "aho1e" 命中黑名单）
```

---

## 错误条件

所有错误都从 `sqids-error` 派生，可用单一 `handler-case` 捕获整个家族：

```lisp
(handler-case
    (cl-sqids:make-sqids :alphabet "ab")
  (cl-sqids:alphabet-too-short-error (c)
    (format t "字母表太短: ~A~%" (cl-sqids:alphabet c))))
```

| 条件类型 | 触发条件 |
|---------|---------|
| `sqids-error` | 所有 cl-sqids 错误的基类 |
| `alphabet-error` | 字母表相关错误的基类（可通过 `alphabet` 读取非法字母表） |
| `alphabet-too-short-error` | 字母表少于 3 个字符 |
| `alphabet-duplicates-error` | 字母表包含重复字符 |
| `alphabet-multibyte-error` | 字母表包含非 ASCII 字符（`code > 127`） |
| `min-length-out-of-range-error` | `min-length` 不在 `[0, 255]` 区间 |
| `max-regenerate-attempts-error` | 黑名单屏蔽使得无法生成合规 ID |
| `unsupported-numbers-type-error` | `encode` 接到了非非负整数或非整数列表的输入 |

---

## 运行测试

测试系统与主系统解耦，依赖 FiveAM：

```bash
sbcl --non-interactive \
     --eval '(require :asdf)' \
     --eval "(pushnew (truename \"/path/to/cl-sqids/\") asdf:*central-registry* :test #'equal)" \
     --eval '(asdf:test-system :cl-sqids)'
```

CCL 同理：

```bash
ccl --batch \
    --eval '(require :asdf)' \
    --eval "(pushnew (truename \"/path/to/cl-sqids/\") asdf:*central-registry* :test #'equal)" \
    --eval '(asdf:test-system :cl-sqids)' \
    --eval '(ccl:quit)'
```

预期输出：

```
Running test suite CL-SQIDS
 Running test SIMPLE-NUMBERS ..
 ...
 Did 281 checks.
    Pass: 281 (100%)
    Skip: 0 ( 0%)
    Fail: 0 ( 0%)
```

也可以在 REPL 中交互运行：

```lisp
(ql:quickload :cl-sqids/tests)
(fiveam:run! :cl-sqids)
```

---

## 兼容性

| 实现 | 版本 | 状态 |
|------|------|------|
| SBCL | 2.6.6（及更新） | ✅ 全部 281 项测试通过 |
| CCL (Clozure CL) | 1.13（及更新） | ✅ 全部 281 项测试通过 |

不依赖任何实现相关包（`sb-ext:` / `ccl:` 等），全部代码为纯 ANSI Common Lisp。
字符串常量与列表常量使用 `defparameter`（而非 `defconstant`）以避免 SBCL 的
"redefining a constant" 警告和 CCL 的实现差异。

---

## 项目结构

```
cl-sqids/
├── cl-sqids.asd              # ASDF 系统定义（含 :cl-sqids/tests 子系统）
├── TASK.md                   # 本次重构任务说明
├── README.md                 # 中文 README（本文档）
├── README.en.md              # English README
├── USAGE.md                  # 中文使用指南
├── USAGE.en.md               # English usage guide
├── LICENSE                   # Apache 2.0
├── src/
│   ├── package.lisp          # 包定义与导出
│   ├── conditions.lisp       # 条件类型层级（带 :report）
│   ├── constants.lisp        # 默认值（defparameter / defconstant 混用）
│   ├── blocklist.lisp        # 3 级黑名单匹配
│   ├── codec.lisp            # 核心算法（修复 8 处 Bug + 宏消除冗余）
│   └── sqids.lisp            # CLOS 类与构造器
└── t/
    ├── packages.lisp         # 测试包
    ├── suite.lisp            # FiveAM 主套件
    ├── test-encoding.lisp    # 编解码向量
    ├── test-minlength.lisp   # MIN-LENGTH 填充级联
    ├── test-blocklist.lisp   # 3 级匹配 + 重排
    ├── test-alphabet.lisp    # 字母表校验
    └── test-roundtrip.lisp   # 往返 / 属性测试
```

---

## 许可证

[Apache License, Version 2.0](./LICENSE) — © David Gao.
