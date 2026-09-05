//
//  ConstellationsSettingsController.swift
//  Constellations
//

import ScreenSaver
import AppKit

/// The configure sheet for the screen saver: one control per setting in `ConstellationsDefaults`.
///
/// Every control writes straight through to the defaults so the saver updates live while the sheet
/// is open. The values are snapshotted on `init`, so "Cancel" can put them all back.
final class ConstellationsSettingsController: NSWindowController {
    
    private enum Setting: Int, CaseIterable {
        case numberOfNodes = 1
        case minSpeed
        case maxSpeed
        case minRadius
        case maxRadius
        case lineDistance
        case backgroundColor
        case nodeColor
        case lineColor
        case renderingEngine
    }
    
    private let defaults: ConstellationsDefaults
    private let onChange: () -> Void
    
    /// The values as they were when the sheet was opened, restored by "Cancel".
    private var snapshot: [Setting: Any] = [:]
    
    private var sliders: [Setting: NSSlider] = [:]
    private var valueLabels: [Setting: NSTextField] = [:]
    private var colorWells: [Setting: NSColorWell] = [:]
    private var enginePopUp: NSPopUpButton?
    
    init(defaults: ConstellationsDefaults, onChange: @escaping () -> Void) {
        self.defaults = defaults
        self.onChange = onChange
        
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
                            styleMask: [.titled],
                            backing: .buffered,
                            defer: false)
        panel.title = "Constellations Settings"
        
        super.init(window: panel)
        
        panel.contentView = buildContentView()
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Presentation
    
    /// Called by the view just before the sheet is handed to the screen saver host.
    func prepareForDisplay() {
        takeSnapshot()
        syncControlsToDefaults()
    }
    
    // MARK: Building the UI
    
    private func buildContentView() -> NSView {
        let grid = NSGridView(numberOfColumns: 3, rows: 0)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 2).xPlacement = .trailing
        
        addHeader("Rendering", to: grid)
        addEngineRow(title: "Engine", to: grid)
        
        addHeader("Nodes", to: grid)
        addSliderRow(for: .numberOfNodes, title: "Count", range: 10...500, to: grid)
        addSliderRow(for: .minRadius, title: "Minimum Radius", range: 0.5...20, to: grid)
        addSliderRow(for: .maxRadius, title: "Maximum Radius", range: 0.5...20, to: grid)
        
        addHeader("Motion", to: grid)
        addSliderRow(for: .minSpeed, title: "Minimum Speed", range: 0...20, to: grid)
        addSliderRow(for: .maxSpeed, title: "Maximum Speed", range: 0...20, to: grid)
        
        addHeader("Connections", to: grid)
        addSliderRow(for: .lineDistance, title: "Line Distance", range: 10...500, to: grid)
        
        addHeader("Colors", to: grid)
        addColorRow(for: .backgroundColor, title: "Background", to: grid)
        addColorRow(for: .nodeColor, title: "Nodes", to: grid)
        addColorRow(for: .lineColor, title: "Lines", to: grid)
        
        let restoreButton = NSButton(title: "Restore Defaults",
                                     target: self,
                                     action: #selector(restoreDefaults))
        restoreButton.bezelStyle = .rounded
        
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        
        let okButton = NSButton(title: "OK", target: self, action: #selector(confirm))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let buttonRow = NSStackView(views: [restoreButton, spacer, cancelButton, okButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        
        let separator = NSBox()
        separator.boxType = .separator
        
        let root = NSStackView(views: [grid, separator, buttonRow])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        
        let contentView = NSView()
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            buttonRow.widthAnchor.constraint(equalTo: grid.widthAnchor),
            separator.widthAnchor.constraint(equalTo: grid.widthAnchor)
        ])
        
        return contentView
    }
    
    private func addHeader(_ title: String, to grid: NSGridView) {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        
        let row = grid.addRow(with: [label])
        row.mergeCells(in: NSRange(location: 0, length: grid.numberOfColumns))
        // The merged cell inherits column 0's trailing placement, which is wrong for a header.
        row.cell(at: 0).xPlacement = .leading
        // A little air above every section but the first one.
        if grid.numberOfRows > 1 {
            row.topPadding = 10
        }
    }
    
    private func addSliderRow(for setting: Setting,
                              title: String,
                              range: ClosedRange<Double>,
                              to grid: NSGridView) {
        let label = NSTextField(labelWithString: title)
        
        let slider = NSSlider(value: value(for: setting),
                              minValue: range.lowerBound,
                              maxValue: range.upperBound,
                              target: self,
                              action: #selector(sliderChanged(_:)))
        slider.tag = setting.rawValue
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        
        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        
        grid.addRow(with: [label, slider, valueLabel])
        
        sliders[setting] = slider
        valueLabels[setting] = valueLabel
        updateValueLabel(for: setting)
    }
    
    private func addEngineRow(title: String, to grid: NSGridView) {
        let label = NSTextField(labelWithString: title)
        
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.menu?.autoenablesItems = false
        let metalIsSupported = ConstellationsMetalRenderer.isSupported
        for engine in ConstellationsDefaults.RenderingEngine.allCases {
            let available = engine != .metal || metalIsSupported
            let item = NSMenuItem(title: available ? engine.displayName
                                                   : "\(engine.displayName) (unavailable)",
                                  action: nil,
                                  keyEquivalent: "")
            item.representedObject = engine
            item.isEnabled = available
            popUp.menu?.addItem(item)
        }
        popUp.target = self
        popUp.action = #selector(engineChanged(_:))
        
        // Keep the pop-up left-aligned in the wide middle column, like the sliders.
        let container = NSStackView(views: [popUp])
        container.orientation = .horizontal
        container.alignment = .centerY
        
        grid.addRow(with: [label, container, NSGridCell.emptyContentView])
        
        enginePopUp = popUp
        syncControl(for: .renderingEngine)
    }
    
    private func addColorRow(for setting: Setting, title: String, to grid: NSGridView) {
        let label = NSTextField(labelWithString: title)
        
        let well = NSColorWell()
        well.tag = setting.rawValue
        well.target = self
        well.action = #selector(colorChanged(_:))
        well.color = color(for: setting)
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: 60).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        
        // Keep the well left-aligned in the wide middle column, like the sliders.
        let container = NSStackView(views: [well])
        container.orientation = .horizontal
        container.alignment = .centerY
        
        grid.addRow(with: [label, container, NSGridCell.emptyContentView])
        
        colorWells[setting] = well
    }
    
    // MARK: Actions
    
    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let setting = Setting(rawValue: sender.tag) else { return }
        
        setValue(sender.doubleValue, for: setting)
        // Keep each minimum at or below its maximum, dragging the partner along when they cross.
        switch setting {
        case .minSpeed: raise(.maxSpeed, toAtLeast: defaults.minSpeed)
        case .maxSpeed: lower(.minSpeed, toAtMost: defaults.maxSpeed)
        case .minRadius: raise(.maxRadius, toAtLeast: defaults.minRadius)
        case .maxRadius: lower(.minRadius, toAtMost: defaults.maxRadius)
        default: break
        }
        
        updateValueLabel(for: setting)
        onChange()
    }
    
    @objc private func colorChanged(_ sender: NSColorWell) {
        guard let setting = Setting(rawValue: sender.tag) else { return }
        setColor(sender.color, for: setting)
        onChange()
    }
    
    @objc private func engineChanged(_ sender: NSPopUpButton) {
        guard let engine = sender.selectedItem?.representedObject as? ConstellationsDefaults.RenderingEngine else { return }
        defaults.renderingEngine = engine
        onChange()
    }
    
    @objc private func restoreDefaults() {
        defaults.reset()
        syncControlsToDefaults()
        onChange()
    }
    
    @objc private func confirm() {
        // The setters have already persisted everything; just close.
        dismiss()
    }
    
    @objc private func cancel() {
        restoreSnapshot()
        syncControlsToDefaults()
        onChange()
        dismiss()
    }
    
    private func dismiss() {
        guard let window = self.window else { return }
        NSColorPanel.shared.close()
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }
    
    // MARK: Reading and writing settings
    
    private func value(for setting: Setting) -> Double {
        switch setting {
        case .numberOfNodes: return Double(defaults.numberOfNodes)
        case .minSpeed: return Double(defaults.minSpeed)
        case .maxSpeed: return Double(defaults.maxSpeed)
        case .minRadius: return Double(defaults.minRadius)
        case .maxRadius: return Double(defaults.maxRadius)
        case .lineDistance: return Double(defaults.lineDistance)
        case .backgroundColor, .nodeColor, .lineColor, .renderingEngine: return 0
        }
    }
    
    private func setValue(_ value: Double, for setting: Setting) {
        switch setting {
        case .numberOfNodes: defaults.numberOfNodes = Int(value.rounded())
        case .minSpeed: defaults.minSpeed = CGFloat(value)
        case .maxSpeed: defaults.maxSpeed = CGFloat(value)
        case .minRadius: defaults.minRadius = CGFloat(value)
        case .maxRadius: defaults.maxRadius = CGFloat(value)
        case .lineDistance: defaults.lineDistance = CGFloat(value)
        case .backgroundColor, .nodeColor, .lineColor, .renderingEngine: break
        }
    }
    
    private func color(for setting: Setting) -> NSColor {
        switch setting {
        case .backgroundColor: return defaults.backgroundColor
        case .nodeColor: return defaults.nodeColor
        case .lineColor: return defaults.lineColor
        default: return .clear
        }
    }
    
    private func setColor(_ color: NSColor, for setting: Setting) {
        switch setting {
        case .backgroundColor: defaults.backgroundColor = color
        case .nodeColor: defaults.nodeColor = color
        case .lineColor: defaults.lineColor = color
        default: break
        }
    }
    
    private func raise(_ setting: Setting, toAtLeast minimum: CGFloat) {
        guard value(for: setting) < Double(minimum) else { return }
        setValue(Double(minimum), for: setting)
        syncControl(for: setting)
    }
    
    private func lower(_ setting: Setting, toAtMost maximum: CGFloat) {
        guard value(for: setting) > Double(maximum) else { return }
        setValue(Double(maximum), for: setting)
        syncControl(for: setting)
    }
    
    // MARK: Keeping the controls in step with the defaults
    
    private func syncControlsToDefaults() {
        Setting.allCases.forEach(syncControl(for:))
    }
    
    private func syncControl(for setting: Setting) {
        if let slider = sliders[setting] {
            slider.doubleValue = value(for: setting)
            updateValueLabel(for: setting)
        }
        colorWells[setting]?.color = color(for: setting)
        if setting == .renderingEngine, let popUp = enginePopUp {
            let index = popUp.itemArray.firstIndex { $0.representedObject as? ConstellationsDefaults.RenderingEngine == defaults.renderingEngine }
            popUp.selectItem(at: index ?? 0)
        }
    }
    
    private func updateValueLabel(for setting: Setting) {
        guard let label = valueLabels[setting] else { return }
        let value = self.value(for: setting)
        label.stringValue = setting == .numberOfNodes
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }
    
    // MARK: Snapshot
    
    private func takeSnapshot() {
        snapshot = [:]
        for setting in Setting.allCases {
            switch setting {
            case .renderingEngine:
                snapshot[setting] = defaults.renderingEngine
            case .backgroundColor, .nodeColor, .lineColor:
                snapshot[setting] = color(for: setting)
            default:
                snapshot[setting] = value(for: setting)
            }
        }
    }
    
    private func restoreSnapshot() {
        for setting in Setting.allCases {
            switch snapshot[setting] {
            case let engine as ConstellationsDefaults.RenderingEngine: defaults.renderingEngine = engine
            case let color as NSColor: setColor(color, for: setting)
            case let value as Double: setValue(value, for: setting)
            default: break
            }
        }
    }
}
