import AppKit
import Combine

/// Mirrors actual window visibility, including changes made through macOS window controls.
final class WindowPresentation:ObservableObject {
    static let shared=WindowPresentation()
    @Published var nanoOnMinimize=UserDefaults.standard.object(forKey:"nanoOnMinimize") as? Bool ?? true {
        didSet {UserDefaults.standard.set(nanoOnMinimize,forKey:"nanoOnMinimize")}
    }
    @Published var autoFit=UserDefaults.standard.bool(forKey:"autoFitPlayerWindow") {
        didSet {UserDefaults.standard.set(autoFit,forKey:"autoFitPlayerWindow");requestFit()}
    }
    private var contentHeight:CGFloat=0
    private var fitWork:DispatchWorkItem?
    func measure(_ height:CGFloat) {
        guard height.isFinite,height>0 else {return}
        if abs(contentHeight-height)>0.5 {contentHeight=height;requestFit()}
    }
    func requestFit() {
        fitWork?.cancel()
        guard autoFit else {return}
        let work=DispatchWorkItem { [weak self] in
            guard let self,self.autoFit else {return}
            AppDelegate.shared?.fitMainContent(self.contentHeight)
        }
        fitWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.05,execute:work)
    }
    @Published private(set) var mini=false
    @Published private(set) var nano=false
    @Published private(set) var fullScreen=false
    func refresh() {
        guard let app=AppDelegate.shared else {return}
        mini=app.miniWindow?.isVisible == true && app.miniWindow?.isMiniaturized == false
        nano=app.pocketWindow?.isVisible == true && app.pocketWindow?.isMiniaturized == false
        fullScreen=app.mainWindow?.styleMask.contains(.fullScreen) == true
    }
}
