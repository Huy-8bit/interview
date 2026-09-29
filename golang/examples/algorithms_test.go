package labs

import (
	"reflect"
	"sort"
	"testing"
)

func TestAlgorithms(t *testing.T) {
	if a, b, ok := TwoSum([]int{3, 3}, 6); !ok || a == b {
		t.Fatal("duplicate pair requires distinct indices")
	}
	a := &Node{Value: 1, Next: &Node{Value: 2}}
	rev := ReverseList(a)
	if rev.Value != 2 || rev.Next != a || a.Next != nil {
		t.Fatal("incorrect reverse links")
	}
	if got := Inorder(&Tree{Value: 2, Left: &Tree{Value: 1}, Right: &Tree{Value: 3}}); !reflect.DeepEqual(got, []int{1, 2, 3}) {
		t.Fatal(got)
	}
	dist := Distances(map[int][]int{1: {2, 3}, 2: {1, 3}, 3: {4}}, 1)
	if dist[4] != 2 || len(dist) != 4 {
		t.Fatal(dist)
	}
	got, err := TopK([]int{5, 1, 5, -1, 2}, 3)
	if err != nil || !reflect.DeepEqual(got, []int{2, 5, 5}) {
		t.Fatal(got, err)
	}
	if _, err := TopK(nil, 1); err == nil {
		t.Fatal("invalid k accepted")
	}
	if LowerBound([]int{1, 2, 2, 4}, 2) != 1 || LowerBound(nil, 1) != 0 || LowerBound([]int{1}, 2) != 1 {
		t.Fatal("lower bound edge")
	}
	if LongestUniqueBytes("abba") != 2 || LongestUniqueBytes("") != 0 {
		t.Fatal("window moved backwards")
	}
	if _, _, ok := TwoSumSorted([]int{1, 2, 5, 8}, 10); !ok {
		t.Fatal("sorted pair")
	}
}
func TestQueueReleasesAndPreservesOrder(t *testing.T) {
	var q Queue[*int]
	for i := 0; i < 3000; i++ {
		n := i
		q.Push(&n)
	}
	for i := 0; i < 3000; i++ {
		v, ok := q.Pop()
		if !ok || *v != i {
			t.Fatalf("item %d", i)
		}
	}
	if q.data != nil || q.head != 0 {
		t.Fatal("empty queue retained storage")
	}
	if _, ok := q.Pop(); ok {
		t.Fatal("empty queue returned a value")
	}
}
func FuzzLowerBound(f *testing.F) {
	f.Add([]byte{2, 1, 2, 4}, uint8(2))
	f.Fuzz(func(t *testing.T, raw []byte, target uint8) {
		nums := make([]int, len(raw))
		for i, v := range raw {
			nums[i] = int(v)
		}
		sort.Ints(nums)
		i := LowerBound(nums, int(target))
		if i < 0 || i > len(nums) {
			t.Fatal("index out of range")
		}
		for j, v := range nums {
			if (j < i && v >= int(target)) || (j >= i && v < int(target)) {
				t.Fatal("partition invariant violated")
			}
		}
	})
}
