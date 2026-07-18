# cl-sqids 重构任务 / Refactor Task

> 主语言：中文（English supplement below each section）

## 1. 背景与目标 / Background & Goals

`cl-sqids` 是 [sqids](https://sqids.org) 的 Common Lisp 实现，用于把非负整数数组编码成短小、唯一、可逆的 ID。

本次重构的 **6 个目标**（用户提出）：

1. 尽量使用 **CLOS** 方案
2. 遵循 **Google Common Lisp Style Guide**
3. 增加 **单元测试**（FiveAM）
4. 同时支持 **SBCL 与 CCL**
5. 使用 **宏 / 公共函数** 降低冗余
6. 增加 **README**（中文为主，英文为辅）

## 2. 现状分析 / Current State

| 文件 | 行数 | 状态 |
|---|---|---|
| `cl-sqids.asd` | 22 | `(in-package :asdf)` 应为 `:asdf-user`；无 `:test-op`；无 `:defsystem-depends-on` |
| `src/package.lisp` | 8 | 仅导出 3 个符号；类名/条件类型未导出 |
| `src/constants.lisp` | 568 | `(defconstant +default-blocklist+ '(...))` 在 SBCL 重定义时报警；CCL 行为不一致 |
| `src/conditions.lisp` | 5 | 条件无 `:report`，错误信息晦涩 |
| `src/core.lisp` | 136 | **存在多处算法 Bug**（见下）；大量代码重复；`setq` 滥用 |
| `src/cl-sqids.lisp` | 58 | `:accessor` + 手动 `setf` 报错是反模式；无 `defgeneric`；构造函数无校验 |
| `README.md` | 1 | 几乎为空 |
| `t/` | — | **不存在** |

### 2.1 算法 Bug（对照官方 sqids-spec 验证）

依据 [sqids-spec](https://github.com/sqids/sqids-spec/blob/main/src/index.ts) 与 [sqids-python](https://github.com/sqids/sqids-python/blob/main/sqids/sqids.py) 官方实现，当前 CL 代码存在以下 **正确性缺陷**：

| # | 位置 | Bug | 后果 |
|---|---|---|---|
| B1 | `to-id` | `while (> x 0)` 应为 `do/while` | `(encode '(0))` 返回空字符（应返回 `"bM"`） |
| B2 | `encode` | 空列表未直接返回 `""` | 行为未定义 |
| B3 | `decode` | 字符不在字母表时应返回 `[]`，当前抛 `bad-alphabet` | 与官方语义不符 |
| B4 | `make-sqids` | **未在构造时一次性 shuffle 字母表** | 同一实例 encode / decode 不一致；官方 `[1,2,3] → "86Rf07"` 失败 |
| B5 | `encode` retry 循环 | 每轮 shuffle 的是同一原始字母表的副本，retry 时 alphabet 不变 | blocklist 命中后永远产生同一 ID，最终抛错 |
| B6 | `encode` retry 循环 | `until (not (null tid))` 在 tid 为 `""`（合法空 ID）时仍退出 | 边界错误 |
| B7 | blocklist 匹配 | 当前 `string=` 全等比较 | 官方为 **大小写不敏感 + 3 级匹配**（短词精确 / 含数字首尾匹配 / 普通词子串匹配） |
| B8 | `make-sqids` | 无任何参数校验 | 缺失：字母表长度≥3、字符唯一、非多字节、`min-length ∈ [0,255]`、blocklist 预清洗 |

### 2.2 风格问题（违反 Google CL Style）

- `.asd` 文件 `(in-package :asdf)` → 应 `:asdf-user`
- `(error (make-condition 'x))` → 应 `(error 'x)`
- `:accessor` 配合手动 `(defmethod (setf slot))` 报错 → 应直接用 `:reader`
- 类方法前无 `defgeneric` 声明
- `loop` 内 `(setq` → 应使用 `with/into`
- `define-condition` 缺 `:report`
- 命名 `do-encode` / `do-decode` → 应去 `do-` 前缀（私有函数加 `%` 前缀或包内可见即可）
- 缺文件头注释（`;;;;` 文件说明 + 版权）
- 缺 docstring

### 2.3 代码冗余

- `(concatenate 'string (subseq alphabet off) (subseq alphabet 0 off))` 出现 2 次
- `(let ((separator (aref nalphabet 0)) (nalphabet-with-separator (subseq nalphabet 1)))` 出现 2 次
- `(shuffle (copy-seq (alphabet instance)))` 出现 2 次
- `to-id` / `to-number` 互为逆运算，可共享常量提取

## 3. 实施方案 / Implementation Plan

### 3.1 目录结构（最终）

```
cl-sqids/
├── cl-sqids.asd              # 主系统 + :cl-sqids/tests 子系统
├── README.md                 # 中文为主，英文为辅
├── TASK.md                   # 本文档
├── LICENSE
├── src/
│   ├── package.lisp          # 包定义，:local-nicknames，完整 :export
│   ├── conditions.lisp       # 带条件层级 + :report
│   ├── constants.lisp        # defparameter 替代 defconstant（CCL/SBCL 兼容）
│   ├── sqids.lisp            # CLOS 类 + make-sqids 构造 + 校验 + defgeneric
│   ├── codec.lisp            # 核心算法（修复 Bug，宏消除冗余）
│   └── blocklist.lisp        # 3 级 blocklist 匹配（拆分独立模块）
└── t/
    ├── packages.lisp         # 五个测试包
    ├── suite.lisp            # 主测试套件
    ├── test-encoding.lisp    # 编解码向量（对照官方）
    ├── test-minlength.lisp   # min-length padding 官方 12 项级联
    ├── test-blocklist.lisp   # 3 级匹配 + 重排
    ├── test-alphabet.lisp    # 字母表校验
    └── test-roundtrip.lisp   # 往返测试
```

### 3.2 文件级任务分解

#### Task A — `cl-sqids.asd`
- `(in-package :asdf-user)`
- 添加 `:defsystem-depends-on (:fiveam)` 仅给子系统；主系统无新依赖
- 在同一文件定义 `:cl-sqids/tests`，`:depends-on (:cl-sqids :fiveam)`
- 主系统 `:in-order-to ((test-op (load-op :cl-sqids/tests)))`
- 子系统 `:in-order-to ((test-op (test-op :cl-sqids/tests)))`，`:perform (test-op ...)` 调 `(5am:run! :cl-sqids)`

#### Task B — `src/package.lisp`
- 使用 `:local-nicknames`（如 `(:5am :fiveam)` 仅测试包用）
- 导出：`sqids` 类、`make-sqids`、`encode` / `decode` 通用函数、所有 `condition` 类型、`sqids-error` 基类
- 内部符号不导出

#### Task C — `src/conditions.lisp`
- 定义基类 `sqids-error` 继承 `error`，带 `:report`
- 派生：`alphabet-too-short` / `alphabet-contains-duplicates` / `alphabet-contains-multibyte` / `min-length-out-of-range` / `max-regenerate-attempts` / `unsupported-numbers-type` / `blocklist-immutable`（如保留只读语义）
- 每个条件带合适的 `:report`

#### Task D — `src/constants.lisp`
- `+default-alphabet+` / `+default-min-length+` / `+default-blocklist+` 改用 `defparameter`（同时解决 SBCL 重定义警告与 CCL 一致性）
- 保持常量命名 `+x+`（约定俗成）但类型为可重赋值
- 文件头注释解释为何用 `defparameter`

#### Task E — `src/sqids.lisp`（CLOS 类 + 构造）
- `(defclass sqids (...) ...)` 所有槽用 `:reader`（真正只读，无需手动覆盖 setf）
- 槽：`alphabet`（已 shuffle）/ `min-length` / `blocklist-exact` / `blocklist-prefix` / `blocklist-substring`（构造时 3 级拆分）/ `original-blocklist`
- `(defgeneric encode (numbers sqids) ...)` / `(defgeneric decode (id sqids) ...)` 带 docstring
- `(defmethod make-instance :after ((sqids sqids)) ...)` 校验，或封装在 `make-sqids` 中
- `make-sqids` 调用 `check-alphabet` / `check-min-length` / `filter-blocklist` / `shuffle` 一次性构造

#### Task F — `src/codec.lisp`（核心算法）
**修复全部 8 个 Bug**，并提取冗余为宏 / `flet`：

- `(defmacro with-rotated-alphabet (alphabet offset &body body))` — rotate + reverse + 主体
- `(defmacro with-separator-split (alphabet &body body))` — separator + 子字母表绑定
- `%shuffle`、`%to-id`、`%to-number`、`%encode-numbers`（递归带 increment）、`%decode-id`
- 全部 `%` 前缀表示内部
- `to-id` 改 `do/while` 等价循环（CL 用 `loop ... while` + 初次执行）
- 增加类型声明 `(declare (type (integer 0) ...))`、`(simple-array character)`
- `decode` 字符不在字母表 → 返回 `nil`

#### Task G — `src/blocklist.lisp`
- `classify-blocklist (word alphabet)` → 返回 `:exact | :ends | :anywhere | nil`（预过滤）
- `split-blocklist (raw alphabet)` → 3 个 set
- `blocked-p (id blocklist-sets)` → 3 级匹配
- 与官方逻辑严格一致（见 sqids-spec `isBlockedId`）

#### Task H — 测试套件 `t/`
**对照官方向量 1:1 移植**（关键数据来自 librarian 报告）：

| 文件 | 测试内容 | 关键向量 |
|---|---|---|
| `test-encoding.lisp` | 基础编码 | `[1,2,3]→"86Rf07"`；`[0]→"bM"`..`[9]→"nJ"`；空列表→`""` |
| `test-minlength.lisp` | min-length 12 项级联 | N=6..65 完整链 |
| `test-blocklist.lisp` | 3 级匹配 + 重排 | `[4572721]→"JExTR"`（不是 `"aho1e"`）；空 blocklist 不重排；decoder 接受 blocked ID；全 blocked 抛错 |
| `test-alphabet.lisp` | 字母表校验 | `"0123456789abcdef"` → `489158`；`"abc"` 合法；`"ab"` / `"aabc"` / 多字节抛错 |
| `test-roundtrip.lisp` | `[0..99]` 往返 + 大数 | `most-positive-fixnum` 往返 |

#### Task I — `README.md`
中文为主（顶部），英文为辅（底部折叠或下半部分）：

- 项目简介 / 简介
- 特性
- 安装（Quicklisp / ASDF / git clone）
- 快速开始（encode / decode 示例）
- API 参考（`make-sqids` 关键字参数表，`encode` / `decode` 签名）
- 自定义（字母表、min-length、blocklist）
- 错误条件类型表
- 测试运行方式
- 兼容性（SBCL / CCL 版本要求）
- 许可证

## 4. 验收标准 / Acceptance Criteria

- [ ] **算法正确**：所有官方测试向量在 SBCL 与 CCL 上通过
  - 关键：`(encode '(1 2 3)) ⇒ "86Rf07"`
  - 关键：`(encode '(4572721)) ⇒ "JExTR"`（blocklist 重排）
  - 关键：`(encode '(0)) ⇒ "bM"`（to-id 边界）
  - 关键：min-length 12 项级联
  - 关键：`(decode "" s) ⇒ nil`；`(decode "*" s) ⇒ nil`
- [ ] **CLOS**：所有公开 API 通过 `sqids` 类与 `defgeneric`；槽只读
- [ ] **Google CL Style**：`in-package`、缩进、命名、`defgeneric`、`:report`、docstring 全部合规
- [ ] **测试**：`(asdf:test-system :cl-sqids)` 在 SBCL 与 CCL 全绿；覆盖率覆盖所有公开 API
- [ ] **SBCL/CCL 兼容**：`defparameter` 替换 `defconstant`；无实现相关警告
- [ ] **DRY**：rotate-alphabet / separator-split 至少 2 个公共宏或 `flet`，重复块为 0
- [ ] **README**：中文为主，含安装/示例/API/兼容性/许可证；英文部分完整

## 5. 执行顺序 / Execution Order

1. **Phase 1 — 基础结构**：asd + package + constants + conditions
2. **Phase 2 — 核心算法**：codec.lisp（修复 Bug） + blocklist.lisp + sqids.lisp（CLOS）
3. **Phase 3 — 测试**：t/*.lisp（官方向量 1:1 移植）
4. **Phase 4 — 文档**：README.md
5. **Phase 5 — 验证**：SBCL + CCL 双实现测试全过

---

## English Summary

Refactor goals: fix 8 algorithm bugs (vs official sqids-spec), adopt CLOS throughout, apply Google Common Lisp Style Guide, add FiveAM tests with 1:1 ported official vectors, support both SBCL and CCL (`defparameter` over `defconstant`), eliminate duplication via macros (`with-rotated-alphabet`, `with-separator-split`), and ship a Chinese-primary README.
