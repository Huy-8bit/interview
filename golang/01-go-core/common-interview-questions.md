# Các tình huống Go core cần hiểu bằng diễn tiến dữ liệu

Tên file được giữ để các link cũ vẫn hoạt động. Nội dung này là bài tổng hợp giải thích, không là ngân hàng câu hỏi trong phần lý thuyết.

## Slice được truyền bằng value nhưng dữ liệu vẫn đổi

Caller tạo a=[1,2,3] dưới dạng slice, callee nhận một bản copy header rồi sửa phần tử đầu. Hai header vẫn trỏ chung backing array, nên caller thấy thay đổi. Append có thêm một nhánh: đủ capacity thì có thể ghi vào array cũ, thiếu capacity thì kết quả dùng array mới. Vì thế API cần nói có mutate input hay trả view chung không; một full slice expression giới hạn append nhưng không deep-copy phần tử.

## Interface không nil dù pointer bên trong nil

Một *ServiceError nil được đưa vào error interface tạo cặp dynamic type=*ServiceError và value=nil. Interface vẫn không nil vì có type. Return nil trực tiếp ở success path tránh typed-nil trap; method receiver phải tự xử lý nil trước khi dereference nếu muốn hỗ trợ nó. Test error identity và type bằng errors.Is/As thay vì so text.

## Pointer, methods và lifetime

Value receiver nhận bản copy state, pointer receiver có thể sửa object qua địa chỉ. Một struct copy vẫn có thể chia sẻ slices/maps phía trong. Compiler quyết định stack/heap theo lifetime và escape, không theo một quy tắc “có & là heap”. Method set của T và *T khác nhau; compiler tự lấy địa chỉ khi gọi method trên biến addressable không có nghĩa T thỏa mọi interface của *T.

## Đồng thời và cleanup

Hai goroutine ghi hai key khác nhau vẫn dùng chung map storage và cần đồng bộ thích hợp. Channel chuyển một slice chỉ copy header nên sender và receiver còn phải giữ ownership của array. Defer đăng ký cleanup ở function boundary, không cuối block hoặc mỗi vòng loop; nhiều files trong loop nên được xử lý bởi helper có lifetime ngắn hơn.

## Từ ví dụ nhỏ tới production

Một parser trả sub-slice nhỏ có thể giữ buffer lớn trong cache; một error constructor typed nil có thể khiến handler báo500 ở đường success; một method copy mutex có thể tạo hai locks bảo vệ cùng map. Những lỗi này cùng bắt nguồn từ việc mô hình value, reference và lifetime không khớp cách code được dùng.

Chạy các ví dụ trong [core tests](../examples/core_test.go) rồi dự đoán output trước khi xem kết quả. Sau đó thay capacity, kiểu receiver hoặc error return và theo dõi điều gì thực sự đổi. Đọc [slices](arrays-slices.md), [interfaces](interfaces.md), [methods](methods.md) và [defer](defer.md) để nối các kết quả với cơ chế đầy đủ. Phần luyện phỏng vấn tách riêng ở [mock interview](../23-mock-interview/README.md).
