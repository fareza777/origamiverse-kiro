class_name OVUndoStack
extends RefCounted
## Command-based undo/redo. Each action is a pair of callables plus a label.

signal changed

var max_history: int = 200
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


## Runs `do_fn` now and records it. Returns false if do_fn returned false explicitly.
func perform(label: String, do_fn: Callable, undo_fn: Callable) -> void:
	do_fn.call()
	push(label, do_fn, undo_fn)


## Records an action that has already been applied.
func push(label: String, do_fn: Callable, undo_fn: Callable) -> void:
	_undo.append({"label": label, "do": do_fn, "undo": undo_fn})
	if _undo.size() > max_history:
		_undo.pop_front()
	_redo.clear()
	changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_label() -> String:
	return _undo.back().label if can_undo() else ""


func redo_label() -> String:
	return _redo.back().label if can_redo() else ""


func undo() -> bool:
	if not can_undo():
		return false
	var a: Dictionary = _undo.pop_back()
	a.undo.call()
	_redo.append(a)
	changed.emit()
	return true


func redo() -> bool:
	if not can_redo():
		return false
	var a: Dictionary = _redo.pop_back()
	a.do.call()
	_undo.append(a)
	changed.emit()
	return true


func clear() -> void:
	_undo.clear()
	_redo.clear()
	changed.emit()


func size() -> int:
	return _undo.size()
