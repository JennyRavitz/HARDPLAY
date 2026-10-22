import AppKit

enum EmbeddedPlaylistLayout {
    static func fittedFrame(current:NSRect,visible:NSRect,height:CGFloat)->NSRect {
        let height=min(visible.height,max(420,ceil(height)))
        let width=min(current.width,visible.width)
        let top=min(visible.maxY,max(visible.minY+height,current.maxY))
        return NSRect(x:min(max(current.minX,visible.minX),visible.maxX-width),y:top-height,width:width,height:height)
    }
    static func frame(current:NSRect,visible:NSRect,tracks:Int)->NSRect {
        // Grow from the top edge; never collapse a user-sized window when attaching a queue.
        let wide=current.width>=840
        let preferredHeight:CGFloat=wide ? 740:760+CGFloat(min(3,max(1,tracks)))*52
        let width=min(visible.width,max(current.width,visible.height<780 ? min(940,visible.width):600))
        let height=min(visible.height,max(current.height,width>=840 ? 740:preferredHeight))
        let x=min(max(current.minX,visible.minX),visible.maxX-width)
        let top=min(visible.maxY,max(visible.minY+height,current.maxY))
        return NSRect(x:x,y:top-height,width:width,height:height)
    }
}
