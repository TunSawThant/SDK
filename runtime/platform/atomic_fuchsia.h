// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_PLATFORM_ATOMIC_FUCHSIA_H_
#define RUNTIME_PLATFORM_ATOMIC_FUCHSIA_H_

#if !defined RUNTIME_PLATFORM_ATOMIC_H_
#error Do not include atomic_fuchsia.h directly. Use atomic.h instead.
#endif

#if !defined(HOST_OS_FUCHSIA)
#error This file should only be included on Fuchsia builds.
#endif

namespace dart {

inline uintptr_t AtomicOperations::FetchAndIncrement(uintptr_t* p) {
  return __sync_fetch_and_add(p, 1);
}

inline intptr_t AtomicOperations::FetchAndIncrement(intptr_t* p) {
  return __sync_fetch_and_add(p, 1);
}

inline void AtomicOperations::IncrementBy(intptr_t* p, intptr_t value) {
  __sync_fetch_and_add(p, value);
}

inline void AtomicOperations::IncrementInt64By(int64_t* p, int64_t value) {
  __sync_fetch_and_add(p, value);
}

inline uintptr_t AtomicOperations::FetchAndDecrement(uintptr_t* p) {
  return __sync_fetch_and_sub(p, 1);
}

inline intptr_t AtomicOperations::FetchAndDecrement(intptr_t* p) {
  return __sync_fetch_and_sub(p, 1);
}

inline void AtomicOperations::DecrementBy(intptr_t* p, intptr_t value) {
  __sync_fetch_and_sub(p, value);
}

inline uword AtomicOperations::CompareAndSwapWord(uword* ptr,
                                                  uword old_value,
                                                  uword new_value) {
  return __sync_val_compare_and_swap(ptr, old_value, new_value);
}

inline uint32_t AtomicOperations::CompareAndSwapUint32(uint32_t* ptr,
                                                       uint32_t old_value,
                                                       uint32_t new_value) {
  return __sync_val_compare_and_swap(ptr, old_value, new_value);
}

template <typename T>
inline T AtomicOperations::LoadAcquire(T* ptr) {
  return __atomic_load_n(ptr, __ATOMIC_ACQUIRE);
}

template <typename T>
inline void AtomicOperations::StoreRelease(T* ptr, T value) {
  __atomic_store_n(ptr, value, __ATOMIC_RELEASE);
}

}  // namespace dart

#endif  // RUNTIME_PLATFORM_ATOMIC_FUCHSIA_H_
