# Protobuf và schema evolution

## Bài toán và ví dụ đầu tiên

Service A deploy thêm field vào message trong khi service B vẫn chạy code cũ. Protobuf dùng field numbers và wire types để encode, nên schema evolution phải giữ identity của field ổn định qua các version.

## Đi từng bước qua một tình huống

Thêm field tương thích cần xét old readers và default/presence semantics. Không tái dùng number của field đã xóa cho một ý nghĩa khác; reserve number/name theo quy trình để tránh dữ liệu cũ bị diễn giải sai. Một scalar zero có thể cần explicit presence nếu nghiệp vụ phân biệt vắng mặt và zero.

## Hiểu cơ chế từ kết quả quan sát

Generated Go struct là biểu diễn trong code, không thay contract wire. Enum mới, unknown fields và oneof cần được client cũ xử lý theo library/version behavior. Đổi tên Go field có thể không đổi wire number nhưng vẫn ảnh hưởng source/API JSON nếu được dùng qua gateway.

## Khái niệm và mô hình làm việc

Wire fields được nhận diện bằng field number; compatibility quan trọng hơn tên generated struct.

## Cơ chế và những ranh giới cần giữ

Không reuse removed field numbers; reserve numbers/names. Additive fields thường dễ rollout hơn đổi type/semantics. Presence khác zero value, repeated/map có behavior riêng.

## Áp dụng vào hệ thống thật

CI kiểm tra backward/forward compatibility và generate bằng pinned protoc/plugins.

## Những đường lỗi cần hiểu

Đổi field meaning không đổi number phá business semantics dù decode thành công; JSON gateway có rules khác binary wire.

## Lần theo bằng chứng khi có sự cố

Test old producer/new consumer và ngược lại; lưu fixtures versioned.

## Đánh đổi và giới hạn sử dụng

Schema contract giảm ambiguity nhưng không thay validation/auth.

## Thực hành, debugging và kết luận

Test old/new writer-reader combinations với fixtures thật, không chỉ compile cùng một version schema. Ghi compatibility rules trong review và tránh log toàn message có secret. Schema gọn giúp transport nhưng validation và authorization vẫn ở boundary ứng dụng.


## Đọc tiếp

- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://protobuf.dev/programming-guides/proto3/)

## Contract example

Đoạn schema minh họa; cần protoc và Go plugin đã pin để generate, không được tuyên bố đã compile trong stdlib labs.

```proto
syntax = "proto3";
package inventory.v1;
option go_package = "example.com/shop/gen/inventory/v1;inventoryv1";
message GetItemRequest { string id = 1; }
message Item {
  string id = 1;
  int64 version = 2;
  optional string display_name = 3;
  reserved 4;
}
service Inventory {
  rpc GetItem(GetItemRequest) returns (Item);
}
```

### Giải thích code và kết quả

Syntax khai báo proto3, package/go_package định danh schema và vị trí generated Go code của ví dụ. Các field numbers1,2,3 là identity trên wire; optional display_name cho phép thể hiện presence theo semantics schema. Reserved4 ngăn tái dùng số đã loại. Service khai báo unary GetItem. Đây là schema minh họa, không được snippets checker Go compile hay protoc generate trong repo; dùng toolchain generator đã pin nếu tích hợp thật.

Presence của display_name cho phép phân biệt omitted với empty theo generated API. Reserved4 ngăn reuse field number cũ. Semantic validation vẫn phải kiểm ID/authorization/version. [Protobuf language guide](https://protobuf.dev/programming-guides/proto3/).
