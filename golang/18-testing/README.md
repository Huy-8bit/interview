# Kiểm chứng hành vi tại đúng boundary

Unit test kiểm rule với dependency kiểm soát; integration test kiểm driver/protocol/database thật; race/fuzz/benchmark trả lời những câu hỏi khác. Các bài hướng dẫn chọn test cho failure và invariant, dùng signals cho concurrency thay vì Sleep đoán lịch chạy. Pass một loại test không chứng minh các loại behavior còn lại.

## Bắt đầu và cách thực hành

Bắt đầu với [unit-testing](unit-testing.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Benchmark tests có statistical comparison](benchmark-testing.md) | P1 |
| [Fuzzing input space và invariants](fuzz-testing.md) | P1 |
| [httptest: recorder versus server](httptest.md) | P1 |
| [Integration testing boundaries thật](integration-testing.md) | P1 |
| [Mocks, fakes và contract tests](mocks.md) | P1 |
| [Race detector workflow](race-detector.md) | P1 |
| [Table-driven tests và subtests](table-driven-tests.md) | P1 |
| [Unit testing business contracts](unit-testing.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
