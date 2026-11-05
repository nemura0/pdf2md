import CoreGraphics

// C callbacks can't capture context, so these helpers are file-level functions, not members.

private func scanState(_ info: UnsafeMutableRawPointer?) -> ScanState? {
    info.map { Unmanaged<ScanState>.fromOpaque($0).takeUnretainedValue() }
}

private func popNumber(_ scanner: CGPDFScannerRef) -> Double? {
    var value: CGPDFReal = 0
    guard CGPDFScannerPopNumber(scanner, &value), value.isFinite else { return nil }
    return Double(value)
}

private func popNumbers(_ scanner: CGPDFScannerRef, count: Int) -> [Double]? {
    var values: [Double] = []
    values.reserveCapacity(count)
    for _ in 0..<count {
        guard let value = popNumber(scanner) else { return nil }
        values.append(value)
    }
    return values.reversed()
}

private func popMatrix(_ scanner: CGPDFScannerRef) -> CGAffineTransform? {
    guard let v = popNumbers(scanner, count: 6) else { return nil }
    return CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
}

private func popPoint(_ scanner: CGPDFScannerRef) -> CGPoint? {
    guard let v = popNumbers(scanner, count: 2) else { return nil }
    return CGPoint(x: v[0], y: v[1])
}

/// A curve operator's endpoint: the last two of its numbers.
private func popCurveEnd(_ scanner: CGPDFScannerRef, operands: Int) -> CGPoint? {
    guard let v = popNumbers(scanner, count: operands) else { return nil }
    return CGPoint(x: v[operands - 2], y: v[operands - 1])
}

private func showPoppedString(_ scanner: CGPDFScannerRef, _ state: ScanState) {
    var string: CGPDFStringRef?
    guard CGPDFScannerPopString(scanner, &string), let string else { return }
    state.beginShow()
    state.show(string)
    state.endShow()
}

/// The C callbacks for `CGPDFScanner`. Each pops its operands in reverse order and forwards to
/// the `ScanState` in the info pointer.
enum OperatorCallbacks {
    static func register(in table: CGPDFOperatorTableRef) {
        registerGraphics(in: table)
        registerTextState(in: table)
        registerTextShowing(in: table)
        registerObjects(in: table)
        registerPaths(in: table)
        registerPainting(in: table)
    }

    private static func registerGraphics(in table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "q") { _, info in scanState(info)?.save() }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in scanState(info)?.restore() }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            if let value = popMatrix(scanner) { scanState(info)?.concatenate(value) }
        }
    }

    private static func registerTextState(in table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "BT") { _, info in scanState(info)?.beginText() }
        CGPDFOperatorTableSetCallback(table, "Tc") { scanner, info in
            if let value = popNumber(scanner) { scanState(info)?.graphics.charSpacing = value }
        }
        CGPDFOperatorTableSetCallback(table, "Tw") { scanner, info in
            if let value = popNumber(scanner) { scanState(info)?.graphics.wordSpacing = value }
        }
        CGPDFOperatorTableSetCallback(table, "Tz") { scanner, info in
            if let value = popNumber(scanner) {
                scanState(info)?.graphics.horizontalScale = value / 100
            }
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            if let value = popNumber(scanner) { scanState(info)?.graphics.leading = value }
        }
        CGPDFOperatorTableSetCallback(table, "Ts") { scanner, info in
            if let value = popNumber(scanner) { scanState(info)?.graphics.rise = value }
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            guard let size = popNumber(scanner) else { return }
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            scanState(info)?.setFont(named: name, size: size, scanner: scanner)
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            if let point = popPoint(scanner) { scanState(info)?.nextLine(point.x, point.y) }
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            guard let point = popPoint(scanner), let state = scanState(info) else { return }
            state.graphics.leading = -point.y
            state.nextLine(point.x, point.y)
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            if let value = popMatrix(scanner) { scanState(info)?.setTextMatrix(value) }
        }
        CGPDFOperatorTableSetCallback(table, "T*") { _, info in
            scanState(info)?.nextLineUsingLeading()
        }
    }

    private static func registerTextShowing(in table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            if let state = scanState(info) { showPoppedString(scanner, state) }
        }
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            guard let state = scanState(info) else { return }
            state.nextLineUsingLeading()
            showPoppedString(scanner, state)
        }
        CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
            guard let state = scanState(info) else { return }
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string,
                let charSpacing = popNumber(scanner), let wordSpacing = popNumber(scanner)
            else { return }
            state.graphics.wordSpacing = wordSpacing
            state.graphics.charSpacing = charSpacing
            state.nextLineUsingLeading()
            state.beginShow()
            state.show(string)
            state.endShow()
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            guard let state = scanState(info) else { return }
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { return }
            state.beginShow()
            for index in 0..<CGPDFArrayGetCount(array) {
                var string: CGPDFStringRef?
                var value: CGPDFReal = 0
                if CGPDFArrayGetString(array, index, &string), let string {
                    state.show(string)
                } else if CGPDFArrayGetNumber(array, index, &value) {
                    state.adjust(Double(value))
                }
            }
            state.endShow()
        }
    }

    private static func registerObjects(in table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            scanState(info)?.drawXObject(named: name, scanner: scanner)
        }
        CGPDFOperatorTableSetCallback(table, "EI") { scanner, info in
            var stream: CGPDFStreamRef?
            guard CGPDFScannerPopStream(scanner, &stream), let stream else { return }
            scanState(info)?.addInlineImage(stream: stream)
        }
    }

    private static func registerPaths(in table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            if let point = popPoint(scanner) { scanState(info)?.moveTo(point) }
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            if let point = popPoint(scanner) { scanState(info)?.lineTo(point) }
        }
        CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
            if let point = popCurveEnd(scanner, operands: 6) { scanState(info)?.curveTo(point) }
        }
        CGPDFOperatorTableSetCallback(table, "v") { scanner, info in
            if let point = popCurveEnd(scanner, operands: 4) { scanState(info)?.curveTo(point) }
        }
        CGPDFOperatorTableSetCallback(table, "y") { scanner, info in
            if let point = popCurveEnd(scanner, operands: 4) { scanState(info)?.curveTo(point) }
        }
        CGPDFOperatorTableSetCallback(table, "h") { _, info in scanState(info)?.closePath() }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let v = popNumbers(scanner, count: 4) else { return }
            scanState(info)?.addRect(CGRect(x: v[0], y: v[1], width: v[2], height: v[3]))
        }
    }

    private static func registerPainting(in table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "S") { _, info in
            scanState(info)?.paintPath(strokes: true, fills: false)
        }
        CGPDFOperatorTableSetCallback(table, "s") { _, info in
            scanState(info)?.closePath()
            scanState(info)?.paintPath(strokes: true, fills: false)
        }
        for name in ["f", "F", "f*"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in
                scanState(info)?.paintPath(strokes: false, fills: true)
            }
        }
        for name in ["B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in
                scanState(info)?.paintPath(strokes: true, fills: true)
            }
        }
        CGPDFOperatorTableSetCallback(table, "n") { _, info in scanState(info)?.clearPath() }
    }
}
