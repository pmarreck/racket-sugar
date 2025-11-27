# HAMT Implementation Notes

Research notes for implementing Hash Array Mapped Tries (HAMT) in Racket.

## Sources

- [Phil Bagwell's "Ideal Hash Trees" (PDF)](https://lampwww.epfl.ch/papers/idealhashtrees.pdf) - Original paper
- [Clojure PersistentHashMap source](https://github.com/clojure/clojure/blob/master/src/jvm/clojure/lang/PersistentHashMap.java)
- [Erlang OTP erl_map.c](https://github.com/erlang/otp/blob/master/erts/emulator/beam/erl_map.c)
- [libhamt - C implementation](https://github.com/mkirchner/hamt)
- [Introduction to HAMT](https://idea.popcount.org/2012-07-25-introduction-to-hamt/)
- [ClojureCLR PersistentHashMap analysis](https://dmiller.github.io/clojure-clr-next/general/2024/07/02/persistent-hash-map-part-1.html)

---

## Core Concept

HAMT combines a **hash table** with a **trie** to achieve:
- O(log₆₄ n) ≈ O(1) lookup/insert/delete (with 64-way branching)
- Persistence via structural sharing (path copying)
- Memory efficiency via bitmap compression

---

## Data Structure

### Node Types (Clojure-style)

```
Node = EmptyNode
     | BitmapIndexedNode(bitmap: u64, array: [Node | Entry]*)
     | ArrayNode(count: int, array: [Node; 64])  ; when mostly full
     | HashCollisionNode(hash: u32, entries: [Entry]*)

Entry = (key, value)
```

### For 64-way branching (our choice):
- **Bitmap**: 64 bits, one per possible child position
- **Array**: Compressed, only contains non-null children
- **Bits per level**: 6 bits (2^6 = 64)
- **Max depth**: ceil(64 / 6) = 11 levels for 64-bit hash

---

## The Bitmap Compression Trick

### Problem
A naive 64-way trie wastes memory: most slots are NULL.

### Solution
Use a bitmap where bit `i` indicates if position `i` has a child.
Store only non-null children in a packed array.

### Finding Array Index
To find where position `i` lives in the packed array:
```
mask = 1 << i
if (bitmap & mask) == 0:
    # Position i is empty - key not found
    return NOT_FOUND
else:
    # Count bits before position i
    index = popcount(bitmap & (mask - 1))
    return array[index]
```

### Pseudocode: popcount
```
popcount(x):
    ; Count number of 1-bits in x
    ; Modern CPUs have POPCNT instruction
    ; Fallback: parallel bit-counting algorithm
    count = 0
    while x != 0:
        count += x & 1
        x >>= 1
    return count
```

---

## Algorithm: Lookup

```
lookup(node, key, hash, level):
    if node is EmptyNode:
        return NOT_FOUND

    if node is HashCollisionNode:
        ; Linear search through colliding entries
        for entry in node.entries:
            if entry.key == key:
                return entry.value
        return NOT_FOUND

    if node is BitmapIndexedNode:
        ; Extract 6 bits for this level
        shift = (10 - level) * 6  ; Start from high bits
        idx = (hash >> shift) & 0x3F  ; 0x3F = 63 = 0b111111

        mask = 1 << idx
        if (node.bitmap & mask) == 0:
            return NOT_FOUND

        array_idx = popcount(node.bitmap & (mask - 1))
        child = node.array[array_idx]

        if child is Entry:
            if child.key == key:
                return child.value
            else:
                return NOT_FOUND
        else:
            return lookup(child, key, hash, level + 1)

    if node is ArrayNode:
        ; Direct indexing (no bitmap needed when mostly full)
        idx = (hash >> ((10 - level) * 6)) & 0x3F
        child = node.array[idx]
        if child is null:
            return NOT_FOUND
        return lookup(child, key, hash, level + 1)
```

---

## Algorithm: Insert (Persistent)

```
insert(node, key, value, hash, level):
    if node is EmptyNode:
        ; Create single-entry node
        idx = (hash >> ((10 - level) * 6)) & 0x3F
        bitmap = 1 << idx
        return BitmapIndexedNode(bitmap, [Entry(key, value)])

    if node is HashCollisionNode:
        if hash != node.hash:
            ; Need to split - create a BitmapIndexedNode
            return split_collision(node, key, value, hash, level)
        else:
            ; Add to collision list (or update existing)
            new_entries = update_or_add(node.entries, key, value)
            return HashCollisionNode(hash, new_entries)

    if node is BitmapIndexedNode:
        idx = (hash >> ((10 - level) * 6)) & 0x3F
        mask = 1 << idx
        array_idx = popcount(node.bitmap & (mask - 1))

        if (node.bitmap & mask) == 0:
            ; Position empty - add new entry
            new_bitmap = node.bitmap | mask
            new_array = array_insert(node.array, array_idx, Entry(key, value))

            ; Convert to ArrayNode if too full (optional optimization)
            if popcount(new_bitmap) > ARRAY_NODE_THRESHOLD:
                return upgrade_to_array_node(new_bitmap, new_array)

            return BitmapIndexedNode(new_bitmap, new_array)
        else:
            ; Position occupied
            existing = node.array[array_idx]

            if existing is Entry:
                if existing.key == key:
                    ; Update existing entry
                    if existing.value == value:
                        return node  ; No change
                    new_array = array_update(node.array, array_idx, Entry(key, value))
                    return BitmapIndexedNode(node.bitmap, new_array)
                else:
                    ; Collision - need to go deeper
                    existing_hash = hash(existing.key)
                    if existing_hash == hash:
                        ; True hash collision
                        collision = HashCollisionNode(hash, [existing, Entry(key, value)])
                        new_array = array_update(node.array, array_idx, collision)
                    else:
                        ; Pseudo-collision - create subtrie
                        subtrie = create_node(existing, existing_hash,
                                             Entry(key, value), hash, level + 1)
                        new_array = array_update(node.array, array_idx, subtrie)
                    return BitmapIndexedNode(node.bitmap, new_array)
            else:
                ; Recurse into child node
                new_child = insert(existing, key, value, hash, level + 1)
                if new_child == existing:
                    return node  ; No change
                new_array = array_update(node.array, array_idx, new_child)
                return BitmapIndexedNode(node.bitmap, new_array)
```

---

## Algorithm: Delete (Persistent)

```
delete(node, key, hash, level):
    if node is EmptyNode:
        return node  ; Nothing to delete

    if node is HashCollisionNode:
        new_entries = remove_by_key(node.entries, key)
        if len(new_entries) == len(node.entries):
            return node  ; Key not found
        if len(new_entries) == 1:
            ; Collapse to single entry (handled by parent)
            return new_entries[0]
        return HashCollisionNode(node.hash, new_entries)

    if node is BitmapIndexedNode:
        idx = (hash >> ((10 - level) * 6)) & 0x3F
        mask = 1 << idx

        if (node.bitmap & mask) == 0:
            return node  ; Key not found

        array_idx = popcount(node.bitmap & (mask - 1))
        existing = node.array[array_idx]

        if existing is Entry:
            if existing.key != key:
                return node  ; Key not found
            ; Remove this entry
            if popcount(node.bitmap) == 1:
                return EmptyNode  ; Last entry
            new_bitmap = node.bitmap & ~mask
            new_array = array_remove(node.array, array_idx)
            return BitmapIndexedNode(new_bitmap, new_array)
        else:
            ; Recurse
            new_child = delete(existing, key, hash, level + 1)
            if new_child == existing:
                return node  ; No change
            if new_child is EmptyNode:
                ; Remove empty child
                if popcount(node.bitmap) == 1:
                    return EmptyNode
                new_bitmap = node.bitmap & ~mask
                new_array = array_remove(node.array, array_idx)
                return BitmapIndexedNode(new_bitmap, new_array)
            if new_child is Entry:
                ; Child collapsed to single entry - inline it
                new_array = array_update(node.array, array_idx, new_child)
                return BitmapIndexedNode(node.bitmap, new_array)
            ; Normal case - updated child
            new_array = array_update(node.array, array_idx, new_child)
            return BitmapIndexedNode(node.bitmap, new_array)
```

---

## Hash Collision Handling

When two keys have the **exact same hash** (after all bits exhausted):

1. **Clojure approach**: Store in a `HashCollisionNode` with linear list
2. **Alternative**: Rehash with a different seed at each level (more complex)

For practical purposes, hash collisions are extremely rare with good 64-bit hashes.

---

## Erlang's Hybrid Approach

Erlang uses **flatmaps for small collections** (≤32 elements):
- Two arrays: sorted keys + corresponding values
- Linear search is fast for small N
- Switches to HAMT at 33+ elements

This optimization could be valuable for our implementation.

---

## Key Optimizations

### 1. ArrayNode for Dense Levels
When a BitmapIndexedNode has >48 children (arbitrary threshold), convert to ArrayNode:
- Direct indexing instead of popcount
- Saves the popcount calculation
- Uses more memory but faster

### 2. Transients (Clojure)
For batch operations, create a "transient" mutable version:
- Mutations happen in-place
- Call `persistent!` when done to freeze
- Huge speedup for building large maps

### 3. Path Copying Optimization
Only copy nodes on the path from root to modified leaf.
All other nodes are shared with the original structure.

### 4. Key Inlining
For leaf entries, store (key, value) directly instead of a separate Entry object.
Reduces indirection and memory.

---

## Implementation Plan for Racket

### Phase 1: Basic BitmapIndexedNode
- Implement popcount (Racket has `bitwise-bit-count`)
- Single node type with bitmap + array
- Basic lookup, insert, contains?

### Phase 2: Hash Collisions
- Add HashCollisionNode for rare collisions
- Proper key equality checking

### Phase 3: Deletion
- Remove operation with node collapsing

### Phase 4: Performance
- Add ArrayNode for dense levels (optional)
- Consider flatmap hybrid for small sizes
- Optimize memory layout

### Phase 5: Persistent Vectors
- Similar HAMT structure for indexed access
- 64-way branching for O(log₆₄ n) operations

---

## Racket-Specific Considerations

### Hash Function
```racket
(eq-hash-code obj)     ; Fast, identity-based
(equal-hash-code obj)  ; Deep equality
```

### Popcount
```racket
(bitwise-bit-count n)  ; Built-in!
```

### Immutable Arrays
Use `vector->immutable-vector` for node arrays.
Or use regular vectors for internal nodes (they're never exposed).

### Typed Racket
Consider adding types for better performance in typed contexts.

---

## Complexity Analysis

| Operation | Time Complexity | Space Complexity |
|-----------|-----------------|------------------|
| Lookup    | O(log₆₄ n) ≈ O(1) | O(1) |
| Insert    | O(log₆₄ n) ≈ O(1) | O(log₆₄ n) new nodes |
| Delete    | O(log₆₄ n) ≈ O(1) | O(log₆₄ n) new nodes |
| Memory    | O(n) | Shared structure |

With 64-way branching:
- 1M elements: max 4 levels
- 1B elements: max 5 levels
- 1T elements: max 7 levels

---

## Next Steps

1. Set up TDD framework with failing tests
2. Implement popcount and bitmap helpers
3. Implement BitmapIndexedNode with lookup
4. Implement insert with path copying
5. Add HashCollisionNode
6. Implement delete
7. Benchmark against current hasheq
8. Integrate with tab-racket `{}` syntax
