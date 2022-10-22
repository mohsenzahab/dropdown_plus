import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';

class DropdownEditingController<T> extends ChangeNotifier {
  T? _value;
  DropdownEditingController({T? value}) : _value = value;

  T? get value => _value;
  set value(T? newValue) {
    if (_value == newValue) return;
    _value = newValue;
    notifyListeners();
  }

  @override
  String toString() => '${describeIdentity(this)}($value)';
}

/// Create a dropdown form field
class DropdownFormField<T> extends StatefulWidget {
  final bool autoFocus;

  /// It will trigger on user search
  final bool Function(T item, String str)? filterFn;

  /// Check item is selected
  final bool Function(T? item1, T? item2)? selectedFn;

  /// Return list of items what need to list for dropdown.
  /// The list may be offline, or remote data from server.
  final Future<List<T>> Function(String str) findFn;

  /// Build dropdown Items, it get called for all dropdown items
  ///  [item] = [dynamic value] List item to build dropdown ListTile
  /// [lasSelectedItem] = [null | dynamic value] last selected item, it gives user chance to highlight selected item
  /// [position] = [0,1,2...] Index of the list item
  /// [focused] = [true | false] is the item if focused, it gives user chance to highlight focused item
  /// [onTap] = [Function] *important! just assign this function to ListTile.onTap  = onTap, incase you missed this,
  /// the click event if the dropdown item will not work.
  ///
  final ListTile Function(
    T item,
    int position,
    bool focused,
    bool selected,
    Function() onTap,
  ) dropdownItemFn;

  /// Build widget to display selected item inside Form Field
  final String Function(T item) displayItemString;

  final InputDecoration? decoration;
  final Color? dropdownColor;
  final DropdownEditingController<T>? controller;
  final void Function(String? item)? onChanged;
  final void Function(T?)? onSaved;
  final String? Function(T?)? validator;

  /// height of the dropdown overlay, Default: 240
  final double? dropdownHeight;

  /// Style the search box text
  final TextStyle? searchTextStyle;

  /// Message to display if the search dows not match with any item, Default : "No matching found!"
  final String emptyText;

  /// Give action text if you want handle the empty search.
  final String emptyActionText;

  /// this function triggers on click of emptyAction button
  final Future<void> Function()? onEmptyActionPressed;

  DropdownFormField({
    Key? key,
    required this.dropdownItemFn,
    required this.displayItemString,
    required this.findFn,
    this.filterFn,
    this.autoFocus = false,
    this.controller,
    this.validator,
    this.decoration,
    this.dropdownColor,
    this.onChanged,
    this.onSaved,
    this.dropdownHeight,
    this.searchTextStyle,
    this.emptyText = "No matching found!",
    this.emptyActionText = 'Create new',
    this.onEmptyActionPressed,
    this.selectedFn,
  }) : super(key: key);

  @override
  DropdownFormFieldState<T> createState() => DropdownFormFieldState<T>();
}

class DropdownFormFieldState<T> extends State<DropdownFormField<T>>
    with SingleTickerProviderStateMixin {
  final FocusNode _widgetFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final ValueNotifier<List<T>?> _listItemsValueNotifier =
      ValueNotifier<List<T>?>([]);
  final TextEditingController _searchTextController = TextEditingController();
  final DropdownEditingController<T>? _controller =
      DropdownEditingController<T>();

  final Function(T?, T?) _selectedFn = (T? item1, T? item2) => item1 == item2;

  bool get _isEmpty => _selectedItem == null;
  bool _isFocused = false;

  OverlayEntry? _overlayEntry;
  OverlayEntry? _overlayBackdropEntry;
  List<T>? _options;
  int _listItemFocusedPosition = 0;
  T? _selectedItem;
  Widget? _displayItem;
  Timer? _debounce;
  String? _lastSearchString;

  DropdownEditingController<T>? get _effectiveController =>
      widget.controller ?? _controller;

  DropdownFormFieldState() : super() {}

  @override
  void initState() {
    super.initState();

    if (widget.autoFocus) _widgetFocusNode.requestFocus();
    _selectedItem = _effectiveController!.value;

    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus && _overlayEntry != null) {
        _removeOverlay();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _debounce?.cancel();
    _searchTextController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // print("_overlayEntry : $_overlayEntry");

    // _displayItem = widget.displayItemString(_selectedItem);

    return CompositedTransformTarget(
        link: this._layerLink,
        // Focus(
        //     autofocus: widget.autoFocus,
        //     focusNode: _widgetFocusNode,
        //     onFocusChange: (focused) {
        //       setState(() {
        //         _isFocused = focused;
        //       });
        //     },
        //     onKey: (focusNode, event) {
        //       return _onKeyPressed(event);
        //     },
        child: TextFormField(
          style: TextStyle(fontSize: 16, color: Colors.black87),
          controller: _searchTextController,
          cursorColor: Colors.black87,
          focusNode: _searchFocusNode,
          decoration: widget.decoration ??
              InputDecoration(
                border: UnderlineInputBorder(),
              ),
          //    inorder   suffixIcon: Icon(Icons.arrow_drop_down),),
          //  backgroundCursorColor: Colors.transparent,
          onChanged: (str) {
            if (_overlayEntry == null) {
              _addOverlay();
            }
            _onTextChanged(str);
          },
          onFieldSubmitted: (str) {
            _searchTextController.value = TextEditingValue(text: "");
            _setValue();
            _removeOverlay();
            _widgetFocusNode.nextFocus();
          },
          // onEditingComplete: () {},
          onSaved: (str) => widget.onSaved?.call(_effectiveController!.value),
          validator: (str) =>
              widget.validator?.call(_effectiveController!.value),
          onTap: () {
            // _widgetFocusNode.requestFocus();
            _toggleOverlay();
          },
        ));
  }

  OverlayEntry _createOverlayEntry() {
    final renderObject = context.findRenderObject() as RenderBox;
    // print(renderObject);
    final Size size = renderObject.size;

    var overlay = OverlayEntry(builder: (context) {
      return Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: this._layerLink,
          showWhenUnlinked: false,
          offset: Offset(0.0, size.height + 3.0),
          child: Material(
              elevation: 4.0,
              child: Container(
                  color: widget.dropdownColor ?? Colors.white70,
                  child: ValueListenableBuilder(
                      valueListenable: _listItemsValueNotifier,
                      builder: (context, List<T>? items, child) {
                        double? boxHeight = null;
                        Widget content;
                        if (items == null) {
                          // if items are loading
                          content = Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        } else if (items.isEmpty) {
                          content = Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  widget.emptyText,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black45),
                                ),
                                if (widget.onEmptyActionPressed != null)
                                  TextButton(
                                    onPressed: () async {
                                      await widget.onEmptyActionPressed!();
                                      _search(_searchTextController.value.text);
                                    },
                                    child: Text(widget.emptyActionText),
                                  ),
                              ],
                            ),
                          );
                        } else {
                          boxHeight = widget.dropdownHeight ?? 240;
                          content = ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: _options!.length,
                              itemBuilder: (context, position) {
                                T item = items[position];
                                Function() onTap = () {
                                  _listItemFocusedPosition = position;
                                  debugPrint('item selected ${item}');
                                  _searchTextController.value =
                                      TextEditingValue(
                                          text: widget.displayItemString(item));
                                  _removeOverlay();
                                  _setValue();
                                };
                                ListTile listTile = widget.dropdownItemFn(
                                  item,
                                  position,
                                  position == _listItemFocusedPosition,
                                  (widget.selectedFn ?? _selectedFn)(
                                      _selectedItem, item),
                                  onTap,
                                );

                                return listTile;
                              });
                        }
                        return SizedBox(
                          height: boxHeight,
                          child: content,
                        );
                      }))),
        ),
      );
    });

    return overlay;
  }

  OverlayEntry _createBackdropOverlay() {
    return OverlayEntry(
        builder: (context) => Positioned(
            left: 0,
            top: 0,
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: GestureDetector(
              onTap: () {
                _removeOverlay();
              },
            )));
  }

  _addOverlay() {
    if (_overlayEntry == null) {
      _search("");
      _overlayBackdropEntry = _createBackdropOverlay();
      _overlayEntry = _createOverlayEntry();
      if (_overlayEntry != null) {
        // Overlay.of(context)!.insert(_overlayEntry!);
        Overlay.of(context)!
            .insertAll([_overlayBackdropEntry!, _overlayEntry!]);
        setState(() {
          _searchFocusNode.requestFocus();
        });
      }
    }
  }

  /// Dettach overlay from the dropdown widget
  _removeOverlay() {
    if (_overlayEntry != null) {
      _overlayBackdropEntry!.remove();
      _overlayEntry!.remove();
      _overlayEntry = null;
      _searchFocusNode.unfocus();
      // _searchTextController.value = TextEditingValue.empty;
      setState(() {});
    }
  }

  _toggleOverlay() {
    if (_overlayEntry == null)
      _addOverlay();
    else
      _removeOverlay();
  }

  _onTextChanged(String? str) {
    widget.onChanged?.call(str);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      // print("_onChanged: $_lastSearchString = $str");
      if (_lastSearchString != str) {
        _lastSearchString = str;
        _search(str ?? "");
      }
    });
  }

  _onKeyPressed(RawKeyEvent event) {
    // print('_onKeyPressed : ${event.character}');
    if (event.isKeyPressed(LogicalKeyboardKey.enter)) {
      if (_searchFocusNode.hasFocus) {
        _toggleOverlay();
      } else {
        _toggleOverlay();
      }
      return false;
    } else if (event.isKeyPressed(LogicalKeyboardKey.escape)) {
      _removeOverlay();
      return true;
    } else if (event.isKeyPressed(LogicalKeyboardKey.arrowDown)) {
      int v = _listItemFocusedPosition;
      v++;
      if (v >= _options!.length) v = 0;
      _listItemFocusedPosition = v;
      _listItemsValueNotifier.value = List<T>.from(_options ?? []);
      return true;
    } else if (event.isKeyPressed(LogicalKeyboardKey.arrowUp)) {
      int v = _listItemFocusedPosition;
      v--;
      if (v < 0) v = _options!.length - 1;
      _listItemFocusedPosition = v;
      _listItemsValueNotifier.value = List<T>.from(_options ?? []);
      return true;
    }
    return false;
  }

  _search(String str) async {
    _listItemsValueNotifier.value = null;

    List<T> items = await widget.findFn(str);

    if (str.isNotEmpty && widget.filterFn != null) {
      items = items.where((item) => widget.filterFn!(item, str)).toList();
    }

    _options = items;

    _listItemsValueNotifier.value = items;

    // print('_search ${_options!.length}');
  }

  _setValue() {
    var item = _options![_listItemFocusedPosition];
    _selectedItem = item;

    _effectiveController!.value = _selectedItem;

    widget.onChanged?.call(_searchTextController.text);

    setState(() {});
  }

  _clearValue() {
    var item;
    _effectiveController!.value = item;

    widget.onChanged?.call(_searchTextController.text);
    _searchTextController.value = TextEditingValue(text: "");
  }
}
