# Memory Management TODO List

## 高優先度

### 1. メモリリークの修正
**File:** `kalloc.zig:60, 74`
```zig
// TODO: Implement proper free when we upgrade to a real allocator
pub fn kfree(ptr: anytype) void
pub fn kdestroy(ptr: anytype) void
```
- 現在、カーネルヒープの解放が未実装
- メモリリークの原因となっている
- スラブアロケータまたはバディシステムの実装を検討

### 2. 非推奨関数の削除
**File:** `user/memory.zig:163-174`
```zig
// DEPRECATED: Old approach - used dynamic stack mapping
pub fn mapCurrentStack(...) !void
```
- 完全にNO-OPとなっている
- 呼び出し元の確認後、削除すべき

## 中優先度

### 3. 重複した定数の統合
**Files:** `config.zig`, `physical.zig`

現在の状態:
```zig
// config.zig
KERNEL_INIT_START: 0x802bf000
KERNEL_INIT_END: 0x802cf000

// physical.zig
PROTECTED_PAGE_TABLE_1: 0x802bf000
PROTECTED_PAGE_TABLE_2: 0x802cf000
```

推奨:
- 統一された名前空間で定義
- 用途を明確にした命名に変更

### 4. 未使用のデバッグコードの削除
**File:** `config.zig:31-33`, `virtual.zig:106`
```zig
PAGE_TABLE_DEBUG_MARKER: 0xDEADBEEF00000000
PAGE_TABLE_DEBUG_WATCHDOG_1: 0x802bf
PAGE_TABLE_DEBUG_WATCHDOG_2: 0x802cf
```
- マーカーは設定されるが、検証されていない
- デバッグが完了したため削除可能

### 5. 未使用関数の削除
**File:** `virtual.zig:236`
```zig
fn walkUserPages(self: *Self, callback: ...) !void
```
- `cloneUserSpace`の簡略化時に作成
- 現在は使用されていない
- 将来的に必要なければ削除

## 低優先度

### 6. 特殊ケース処理の見直し
**File:** `virtual.zig:66-73`
```zig
if (table_addr == config.MemoryLayout.KERNEL_INIT_END) {
    // Special case: KERNEL_INIT_END
    ...
}
```
- なぜこの特殊処理が必要か不明
- 調査して、不要なら削除

### 7. 重複チェックの統合
**File:** `virtual.zig:184, 202`
```zig
if (new_page == config.MemoryLayout.KERNEL_INIT_START) {
    allocator.freeFrame(new_page);
    return error.InvalidPageAddress;
}
```
- 同じチェックが2箇所に存在
- ヘルパー関数への抽出を検討

### 8. ハードコード値の設定可能化
**File:** `allocator.zig:30-31`
```zig
.base = 0x80000000,
.size = 256 * 1024 * 1024, // 256MB固定
```
- メモリサイズが決め打ち
- 設定可能にするか、動的検出を実装

## 将来的な改善

### 9. Copy-on-Write (COW) の実装
**File:** `virtual.zig:417`
```zig
// This creates a simple copy of all user pages (no COW yet)
```
- フォーク時のメモリ効率改善
- ページフォルトハンドラの拡張が必要

### 10. デマンドページングの実装
- 必要時のみページを割り当て
- メモリ使用効率の向上

### 11. スワップサポート
- ディスクへのページスワップアウト
- より多くのプロセスをサポート

## コード品質改善

### 12. エラーハンドリングの一貫性
- エラー型の統一
- より詳細なエラー情報の提供

### 13. ドキュメントの追加
- 各関数の詳細な説明
- 使用例の追加
- アーキテクチャ図の作成

### 14. テストの追加
- ユニットテストの実装
- 境界値テスト
- ストレステスト

## パフォーマンス最適化

### 15. TLBシュートダウンの最適化
- 現在は保守的にsfence.vmaを使用
- より細かい制御で性能向上可能

### 16. 大ページ（2MB/1GB）のサポート
- 大きなメモリ領域に対して効率的
- TLBミスの削減

## 完了済み

- [x] `CRITICAL_KERNEL_ADDR`関連のデバッグコード削除
- [x] ハードウェアワークアラウンド（0x8021c000）の削除
- [x] `extractVPN`ヘルパー関数の追加
- [x] `mapKernelRegions`による重複コード削減
- [x] ビットマップ検索の最適化（`@ctz`使用）