/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#ifndef LIBKERN_PATCH_H
#define LIBKERN_PATCH_H

#define DYLD_INTERPOSE(_replacement, _replacee)                 \
    __attribute__((used))                                       \
    static struct {                                             \
        const void *replacement;                                \
        const void *replacee;                                   \
    } _interpose_##_replacee                                    \
    __attribute__((section("__DATA,__interpose"))) = {          \
        (const void *)(unsigned long)&_replacement,             \
        (const void *)(unsigned long)&_replacee                 \
    }

#define LIBKERN_DEFINE_INTERPOSE_PATCHABLE(name)                \
    extern void name(void);                                     \
    extern void name##__orig_thunk(void);                       \
    extern void name##__interpose_entry(void);                  \
                                                                \
    __attribute__((used, section("__DATA,__lkswz")))            \
    void *name##__ptr = (void *)&name##__orig_thunk;            \
                                                                \
    __asm__(                                                    \
        ".section __TEXT,__text,regular,pure_instructions\n"    \
        ".private_extern _" #name "__orig_thunk\n"              \
        ".p2align 2\n"                                          \
        "_" #name "__orig_thunk:\n"                             \
        "    b _" #name "\n"                                    \
                                                                \
        ".private_extern _" #name "__interpose_entry\n"         \
        ".p2align 2\n"                                          \
        "_" #name "__interpose_entry:\n"                        \
        "    adrp x16, _" #name "__ptr@PAGE\n"                  \
        "    ldr  x16, [x16, _" #name "__ptr@PAGEOFF]\n"        \
        "    br   x16\n"                                        \
    );                                                          \
                                                                \
    DYLD_INTERPOSE(name##__interpose_entry, name)

#define LIBKERN_DEFINE_PATCHABLE(ret, name, params)             \
    static ret name##__impl params;                             \
                                                                \
    ret name params;                                            \
                                                                \
    __attribute__((used, section("__DATA,__lkswz")))            \
    void *name##__ptr = (void *)&name##__impl;                  \
                                                                \
    __asm__(                                                    \
        ".section __TEXT,__text,regular,pure_instructions\n"    \
        ".globl _" #name "\n"                                   \
        ".p2align 2\n"                                          \
        "_" #name ":\n"                                         \
        "    adrp x16, _" #name "__ptr@PAGE\n"                  \
        "    ldr  x16, [x16, _" #name "__ptr@PAGEOFF]\n"        \
        "    br   x16\n"                                        \
    );                                                          \
                                                                \
    static __attribute__((noinline, optnone, used))             \
    ret name##__impl params

#define LIBKERN__DECLARE_PATCHABLE(ret, name, params)           \
    ret name params;                                            \
    extern void *name##__ptr

#define LIBKERN_PATCH(ret, name, params, ...)                   \
    extern void *name##__ptr;                                   \
    static ret (*name##__orig) params;                          \
    static ret name##__swz params __VA_ARGS__                   \
    static void name##__install(void) {                         \
        name##__orig = (ret (*) params)name##__ptr;             \
        name##__ptr  = (void *)name##__swz;                     \
    }                                                           \
    static void name##__uninstall(void) {                       \
        name##__ptr  = (void *)name##__orig;                    \
    }                                                           \
    extern int name##__need_semi

#define LIBKERN_INSTALL_PATCH(name)     name##__install()
#define LIBKERN_UNINSTALL_PATCH(name)   name##__uninstall()

#endif /* LIBKERN_PATCH_H */
