# Azeria Labs ARM Assembly Tutorial

## What is This Resource?

**Azeria Labs** is a well-known educational resource for learning ARM assembly
programming, reverse engineering, and exploit development. Their tutorial series
"Writing ARM Assembly" provides a comprehensive introduction to ARM assembly
language.

**URL:** https://azeria-labs.com/writing-arm-assembly-part-1/ (starting point
for the series)

## What Does the Tutorial Series Cover?

The "Writing ARM Assembly" tutorial series provides a comprehensive guide to ARM
assembly programming, progressing from basics to advanced topics. The series
covers:

- **Basic ARM assembly concepts** - Introduction to ARM architecture and
  assembly syntax
- **Setting up the development environment** - Tools and setup for writing ARM
  assembly
- **Fundamental instructions** - Basic ARM instructions and their usage
- **Registers and memory** - Understanding ARM registers and memory operations
- **Control flow** - Branches, loops, and conditional execution
- **Functions and calling conventions** - How to write and call functions
- **Advanced topics** - More complex assembly programming techniques
- **Practical examples** - Working code examples throughout each part

## Why This Resource is Useful

1. **Clear explanations** - Azeria Labs tutorials are known for being
   beginner-friendly with clear explanations and examples

2. **Practical examples** - Includes working code examples you can compile and
   run

3. **ARM-focused** - Specifically tailored for ARM architecture (relevant for
   ARM64 development)

4. **Progressive learning** - Part of a series that builds from basics to
   advanced topics

5. **Industry standard** - Widely referenced in the security and reverse
   engineering communities

## How It Relates to This Project

While this project focuses on **ARM64** (AArch64) assembly, Azeria Labs
tutorials often cover **ARM32** (ARMv7) as well. However, many concepts
translate between the two:

- **Register usage** - Similar register naming conventions (though ARM64 has
  more registers)
- **Instruction syntax** - Similar assembly syntax patterns
- **Memory operations** - Similar concepts for loading/storing data
- **System calls** - Similar approaches to making system calls

The tutorials provide a solid foundation for understanding ARM assembly concepts
that apply to ARM64 development.

## When to Use This Resource

- **Learning ARM assembly basics** - If you're new to ARM assembly programming
- **Understanding ARM concepts** - To learn fundamental ARM architecture
  concepts
- **Reference material** - As a reference for ARM instruction syntax and usage
- **Complementary learning** - To supplement hands-on work with this project

## Note on Architecture Differences

Keep in mind that:

- Azeria Labs tutorials may focus on **ARM32** (32-bit ARM)
- This project uses **ARM64** (64-bit ARM/AArch64)
- While concepts are similar, some instructions and register names differ
- ARM64 has more registers (31 general-purpose vs 15 in ARM32)
- ARM64 uses different calling conventions

Use the tutorials for conceptual understanding, but verify ARM64-specific
details in ARM64 documentation or your actual code.

## Additional Resources

The "Writing ARM Assembly" series consists of multiple parts that progressively
build your understanding. Azeria Labs also offers other tutorial series
covering:

- Reverse engineering ARM binaries
- Exploit development on ARM
- ARM debugging techniques

Check their website for all parts of the series and related resources.
