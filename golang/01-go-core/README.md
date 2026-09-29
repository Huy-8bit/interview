# Giá trị, kiểu dữ liệu và ownership trong Go

Module này giải thích vì sao copy một slice vẫn chia sẻ dữ liệu, vì sao interface chứa nil pointer có thể không nil, và vì sao defer chạy khác trực giác về block scope. Đi từ output của ví dụ đến value/reference/lifetime giúp các bài concurrency sau không trở thành học thuộc quy tắc. Bắt đầu arrays-slices, rồi maps, interfaces/nil, methods và cleanup/errors.

## Bắt đầu và cách thực hành

Bắt đầu với [arrays-slices](arrays-slices.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Arrays, slices và ownership](arrays-slices.md) | P0 |
| [Go core: luyện giải thích code](common-interview-questions.md) | Practice |
| [Defer: evaluation, LIFO và cleanup](defer.md) | P1 |
| [Error handling và error chains](errors.md) | P0 |
| [Generics và constraints](generics.md) | P1 |
| [Go philosophy](go-philosophy.md) | P1 |
| [Interfaces: behavior, representation và typed nil](interfaces.md) | P0 |
| [Maps: hashing, growth và concurrent access](maps.md) | P0 |
| [Methods và method sets](methods.md) | P1 |
| [nil: zero value theo từng loại](nil.md) | P0 |
| [Packages và modules](packages-modules.md) | P1 |
| [Panic và recover](panic-recover.md) | P1 |
| [Strings, runes và bytes](strings-runes-bytes.md) | P1 |
| [Struct layout và composition](struct.md) | P1 |
| [Value versus pointer](value-vs-pointer.md) | P1 |
| [Variables, types và zero values](variables-types.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
