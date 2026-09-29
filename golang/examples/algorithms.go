package labs

import (
	"container/heap"
	"errors"
)

// TwoSum returns distinct indices for one pair. Integer arithmetic is assumed
// not to overflow; validate a bounded input domain if that is not guaranteed.
func TwoSum(nums []int, target int) (int, int, bool) {
	seen := make(map[int]int, len(nums))
	for i, n := range nums {
		if j, ok := seen[target-n]; ok {
			return j, i, true
		}
		seen[n] = i
	}
	return 0, 0, false
}

type Node struct {
	Value int
	Next  *Node
}

func ReverseList(head *Node) *Node {
	var prev *Node
	for head != nil {
		next := head.Next
		head.Next = prev
		prev = head
		head = next
	}
	return prev
}

type Queue[T any] struct {
	data []T
	head int
}

func (q *Queue[T]) Push(v T) { q.data = append(q.data, v) }
func (q *Queue[T]) Pop() (T, bool) {
	var zero T
	if q.head == len(q.data) {
		return zero, false
	}
	value := q.data[q.head]
	q.data[q.head] = zero
	q.head++
	if q.head == len(q.data) {
		q.data = nil
		q.head = 0
	} else if q.head > 1024 && q.head > len(q.data)/2 {
		q.data = append([]T(nil), q.data[q.head:]...)
		q.head = 0
	}
	return value, true
}

type Tree struct {
	Value       int
	Left, Right *Tree
}

func Inorder(root *Tree) []int {
	var result []int
	var stack []*Tree
	for root != nil || len(stack) > 0 {
		for root != nil {
			stack = append(stack, root)
			root = root.Left
		}
		root = stack[len(stack)-1]
		stack[len(stack)-1] = nil
		stack = stack[:len(stack)-1]
		result = append(result, root.Value)
		root = root.Right
	}
	return result
}
func Distances(graph map[int][]int, start int) map[int]int {
	distance := map[int]int{start: 0}
	var q Queue[int]
	q.Push(start)
	for {
		v, ok := q.Pop()
		if !ok {
			break
		}
		for _, next := range graph[v] {
			if _, seen := distance[next]; !seen {
				distance[next] = distance[v] + 1
				q.Push(next)
			}
		}
	}
	return distance
}

type minInts []int

func (h minInts) Len() int           { return len(h) }
func (h minInts) Less(i, j int) bool { return h[i] < h[j] }
func (h minInts) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *minInts) Push(x any)        { *h = append(*h, x.(int)) }
func (h *minInts) Pop() any          { old := *h; n := len(old); x := old[n-1]; *h = old[:n-1]; return x }

// TopK returns the k largest values in ascending order, including duplicates.
func TopK(nums []int, k int) ([]int, error) {
	if k < 0 || k > len(nums) {
		return nil, errors.New("k out of range")
	}
	if k == 0 {
		return []int{}, nil
	}
	h := &minInts{}
	heap.Init(h)
	for _, n := range nums {
		if h.Len() < k {
			heap.Push(h, n)
		} else if n > (*h)[0] {
			(*h)[0] = n
			heap.Fix(h, 0)
		}
	}
	out := make([]int, k)
	for i := range out {
		out[i] = heap.Pop(h).(int)
	}
	return out, nil
}

// LowerBound returns the first index i such that sorted[i]>=target, or len(sorted).
func LowerBound(sorted []int, target int) int {
	left, right := 0, len(sorted)
	for left < right {
		mid := left + (right-left)/2
		if sorted[mid] < target {
			left = mid + 1
		} else {
			right = mid
		}
	}
	return left
}

// LongestUniqueBytes counts unique bytes, not Unicode grapheme clusters.
func LongestUniqueBytes(s string) int {
	var last [256]int
	left, best := 0, 0
	for right := 0; right < len(s); right++ {
		b := s[right]
		if last[b] > left {
			left = last[b]
		}
		if right-left+1 > best {
			best = right - left + 1
		}
		last[b] = right + 1
	}
	return best
}
func TwoSumSorted(nums []int, target int) (int, int, bool) {
	left, right := 0, len(nums)-1
	for left < right {
		sum := nums[left] + nums[right]
		if sum == target {
			return left, right, true
		}
		if sum < target {
			left++
		} else {
			right--
		}
	}
	return 0, 0, false
}
