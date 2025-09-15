# Kissat SAT Solver 项目文档

## 项目概述

Kissat 是一个用 C 语言编写的"简洁高效的底层 SAT 求解器"（keep it simple and clean bare metal SAT solver）。它是 CaDiCaL 求解器移植到 C 语言的版本，具有改进的数据结构、更好的内处理调度以及优化的算法和实现。

### 基本信息
- **版本**: 4.0.1
- **语言**: C
- **许可证**: MIT
- **主要作者**: Armin Biere 等
- **用途**: 布尔可满足性问题（SAT）求解

### 核心特性
- 高效的 CDCL（Conflict-Driven Clause Learning）算法实现
- 支持 IPASIR 接口标准
- 快速变量消除预处理
- 幸运相位（Lucky phases）
- 推理跳跃（Reason jumping）
- 子句收集和垃圾回收
- 证明生成和验证
- 多种配置模式（basic, default, plain, sat, unsat）

## 目录结构

```
kissat-rel-4.0.1/
├── README.md                   # 项目说明文档
├── LICENSE                     # MIT 许可证
├── VERSION                     # 版本号文件（4.0.1）
├── NEWS.md                     # 版本更新记录
├── CONTRIBUTING                # 贡献指南
├── configure                   # 主配置脚本
├── makefile.in                 # Makefile 模板
├── scripts/                    # 构建和工具脚本
│   ├── build-and-test-all-configurations.sh
│   ├── determine-coverage.sh
│   ├── filter-coverage-output.sh
│   ├── generate-build-header.sh
│   ├── make-source-release.sh
│   └── prepare-competition.sh
├── src/                        # 核心源代码目录
│   ├── kissat.h               # 主要 API 接口
│   ├── main.c                 # 程序入口点
│   ├── internal.h             # 内部数据结构定义
│   ├── internal.c             # 核心 API 实现
│   ├── application.c          # 应用程序逻辑
│   ├── search.c               # 主搜索算法
│   ├── [大量核心模块文件]     # 详见下文模块说明
│   └── configure              # 源码目录配置脚本
└── test/                       # 测试代码目录
    ├── test.c                 # 测试框架主文件
    ├── test*.c                # 各模块测试文件
    ├── cnf/                   # 测试用 CNF 文件
    └── configure              # 测试配置脚本
```

## 核心模块详细说明

### 1. 核心接口层 (API Layer)

#### `src/kissat.h` - 主要 API 接口
- **职责**: 定义对外公开的 IPASIR 标准接口
- **核心函数**:
  - `kissat_init()`: 初始化求解器实例
  - `kissat_add(solver, lit)`: 添加文字到当前子句
  - `kissat_solve(solver)`: 执行 SAT 求解
  - `kissat_value(solver, lit)`: 获取变量赋值
  - `kissat_release(solver)`: 释放求解器资源
- **扩展功能**: 配置管理、统计信息、证明生成控制

#### `src/main.c` - 程序入口
- **职责**: 命令行工具入口点，信号处理
- **核心逻辑**: 
  - 初始化求解器和信号处理器
  - 调用应用程序主逻辑
  - 处理程序终止和清理

#### `src/application.c` - 应用程序逻辑
- **职责**: 命令行参数解析、文件 I/O、主控制流
- **核心功能**:
  - DIMACS 格式文件解析
  - 证明文件生成
  - 配置选项处理
  - 求解结果输出

### 2. 核心数据结构层

#### `src/internal.h` - 内部数据结构定义
- **职责**: 定义求解器的主要数据结构 `kissat`
- **关键组件**:
  - `assigned *assigned`: 变量赋值数组
  - `value *values`: 变量取值数组
  - `unsigned_array trail`: 赋值轨迹
  - `heap scores`: 变量活跃度堆
  - `queue queue`: 传播队列
  - `frames frames`: 决策层次栈
  - `statistics statistics`: 统计信息
  - `options options`: 配置选项

#### `src/internal.c` - 核心 API 实现
- **职责**: 实现 kissat.h 中定义的核心接口
- **核心函数**:
  - `kissat_solve()`: 主求解入口，调用搜索算法
  - `kissat_add()`: 子句添加逻辑，处理单元传播
  - `kissat_value()`: 变量赋值查询
  - 求解器生命周期管理

### 3. 搜索算法层

#### `src/search.c` - 主搜索算法
- **职责**: 实现 CDCL 主搜索循环
- **核心算法**:
  - 决策变量选择
  - 布尔约束传播（BCP）
  - 冲突分析和学习
  - 重启和相位管理
- **依赖模块**: decide.c, analyze.c, propagate.c, restart.c

#### `src/decide.c` - 决策策略
- **职责**: 变量选择和相位决定
- **核心逻辑**:
  - VSIDS 启发式评分
  - 变量活跃度管理
  - 相位保存策略

#### `src/analyze.c` - 冲突分析
- **职责**: 冲突子句分析和学习子句生成
- **核心算法**:
  - 第一唯一蕴含点（1UIP）计算
  - 学习子句最小化
  - 回跳层次确定

#### `src/propsearch.c` / `src/propdense.c` - 传播引擎
- **职责**: 布尔约束传播实现
- **优化特性**:
  - 监视文字（watched literals）
  - 稠密传播优化
  - 二元子句特殊处理

### 4. 预处理层

#### `src/preprocess.c` - 预处理控制
- **职责**: 协调各种预处理技术
- **预处理技术**: 变量消除、等价性检测、子句简化

#### `src/eliminate.c` - 变量消除
- **职责**: 通过分辨消除冗余变量
- **算法**: 有界变量消除（BVE）

#### `src/fastel.c` - 快速变量消除
- **职责**: 预处理阶段的快速变量消除
- **特性**: 优化的消除策略和数据结构

#### `src/equivalences.c` - 等价性处理
- **职责**: 检测和处理变量等价关系
- **技术**: 合同性闭包算法

### 5. 内处理层

#### `src/reduce.c` - 子句数据库管理
- **职责**: 学习子句的收集和删除
- **策略**: LBD（Literal Block Distance）评分

#### `src/vivify.c` - 子句活化
- **职责**: 通过赋值尝试缩短子句
- **层级**: tier0-tier3 不同强度的活化

#### `src/probe.c` - 探测
- **职责**: 通过试探性赋值发现等价关系
- **技术**: 失败文字检测

### 6. 数据结构支持层

#### `src/arena.c` - 内存竞技场
- **职责**: 高效的内存分配和管理
- **特性**: 引用基址的内存布局

#### `src/clause.c` - 子句管理
- **职责**: 子句的创建、访问和删除
- **优化**: 内存紧凑的子句表示

#### `src/stack.c` / `src/vector.c` - 容器数据结构
- **职责**: 动态数组和栈的实现
- **特性**: 类型安全的宏定义

#### `src/heap.c` - 堆数据结构
- **职责**: 优先队列实现，用于变量选择
- **用途**: VSIDS 评分管理

### 7. 工具和配置层

#### `src/options.c` - 选项管理
- **职责**: 配置参数的定义和访问
- **功能**: 动态选项设置和验证

#### `src/config.c` - 配置管理
- **职责**: 预定义配置的管理
- **配置类型**: basic, default, plain, sat, unsat

#### `src/parse.c` - 文件解析
- **职责**: DIMACS 格式文件解析
- **特性**: 错误处理和格式验证

#### `src/proof.c` - 证明生成
- **职责**: DRAT 证明轨迹生成
- **格式**: 支持二进制和文本格式

### 8. 测试框架

#### `test/test.c` - 测试框架主文件
- **职责**: 测试执行框架和报告
- **功能**: 单元测试协调和结果统计

#### `test/test*.c` - 各模块测试
- **覆盖范围**: 
  - 数据结构测试（testvector.c, teststack.c）
  - 算法测试（testsolve.c, testparse.c）
  - 配置测试（testconfig.c, testoptions.c）
  - I/O 测试（testfile.c）

## 项目依赖与配置

### 构建依赖
- **编译器**: GCC 或 Clang
- **构建工具**: Make
- **可选依赖**: 
  - 压缩库（用于压缩文件 I/O）
  - Coverage 工具（gcov）

### 配置选项
- **调试选项**: `--debug`, `--check`, `--logging`
- **优化选项**: `--optimize`, `--profile`
- **功能选项**: `--proof`, `--shared`, `--kitten`
- **架构选项**: `--m32`, `--static`

### 预定义配置
- **default**: 标准配置，平衡性能和功能
- **basic**: 基本功能，最小开销
- **plain**: 无预处理的纯搜索
- **sat**: 针对可满足实例优化
- **unsat**: 针对不可满足实例优化

## 项目启动/构建步骤

### 基本构建
```bash
# 1. 配置项目
./configure

# 2. 编译
make

# 3. 测试
make test

# 4. 运行
./build/kissat input.cnf
```

### 自定义配置构建
```bash
# 调试版本
./configure --debug --check

# 性能优化版本
./configure --optimize

# 特定配置
./configure --competition

# 32位版本
./configure --m32

# 共享库版本
./configure --shared
```

### 使用示例
```bash
# 基本求解
./build/kissat problem.cnf

# 生成证明
./build/kissat problem.cnf proof.drat

# 设置时间限制
./build/kissat --time=60 problem.cnf

# 使用特定配置
./build/kissat --sat problem.cnf

# 详细输出
./build/kissat --verbose problem.cnf
```

### 文件格式
- **输入**: DIMACS CNF 格式
- **输出**: SAT/UNSAT 结果和可选的满足赋值
- **证明**: DRAT 格式证明轨迹

## 核心算法流程

### SAT 求解主流程
1. **初始化**: 创建求解器实例，设置配置
2. **解析**: 读取 DIMACS 文件，构建子句数据库
3. **预处理**: 应用变量消除、等价性检测等技术
4. **搜索循环**:
   - 单元传播
   - 决策变量选择
   - 冲突检测
   - 冲突分析和学习
   - 回跳
   - 重启判断
5. **后处理**: 解的扩展和验证
6. **结果输出**: 返回 SAT/UNSAT 和可选的满足赋值

### 关键数据流
- **子句** → **监视文字** → **传播队列** → **赋值轨迹**
- **冲突** → **分析栈** → **学习子句** → **子句数据库**
- **变量活跃度** → **评分堆** → **决策选择**

这个项目体现了现代 SAT 求解器的精髓，通过模块化设计实现了高效的布尔可满足性问题求解，是研究和应用 SAT 技术的重要参考实现。
