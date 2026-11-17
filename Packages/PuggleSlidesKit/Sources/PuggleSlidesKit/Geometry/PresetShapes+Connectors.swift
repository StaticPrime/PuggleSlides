// DrawingML preset shapes, transcribed from ECMA-376 Part 1's presetShapeDefinitions.xml. See PresetShapeDefinition
// for the statement syntax and the errata fixed.

extension PresetShapeSource {
    static let connectors: [String: String] = [
        "bentConnector2": """
            rect l t r b
            path fill=none
            M l t
            L r t
            L r b
            """,
        "bentConnector3": """
            av adj1 val 50000
            gd x1 */ w adj1 100000
            ahXY gdRefX=adj1 minX=-2147483647 maxX=2147483647 x=x1 y=vc
            rect l t r b
            path fill=none
            M l t
            L x1 t
            L x1 b
            L r b
            """,
        "bentConnector4": """
            av adj1 val 50000
            av adj2 val 50000
            gd x1 */ w adj1 100000
            gd x2 +/ x1 r 2
            gd y2 */ h adj2 100000
            gd y1 +/ t y2 2
            ahXY gdRefX=adj1 minX=-2147483647 maxX=2147483647 x=x1 y=y1
            ahXY gdRefY=adj2 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            rect l t r b
            path fill=none
            M l t
            L x1 t
            L x1 y2
            L r y2
            L r b
            """,
        "bentConnector5": """
            av adj1 val 50000
            av adj2 val 50000
            av adj3 val 50000
            gd x1 */ w adj1 100000
            gd x3 */ w adj3 100000
            gd x2 +/ x1 x3 2
            gd y2 */ h adj2 100000
            gd y1 +/ t y2 2
            gd y3 +/ b y2 2
            ahXY gdRefX=adj1 minX=-2147483647 maxX=2147483647 x=x1 y=y1
            ahXY gdRefY=adj2 minY=-2147483647 maxY=2147483647 x=x2 y=y2
            ahXY gdRefX=adj3 minX=-2147483647 maxX=2147483647 x=x3 y=y3
            rect l t r b
            path fill=none
            M l t
            L x1 t
            L x1 y2
            L x3 y2
            L x3 b
            L r b
            """,
        "curvedConnector2": """
            rect l t r b
            path fill=none
            M l t
            C wd2 t r hd2 r b
            """,
        "curvedConnector3": """
            av adj1 val 50000
            gd x2 */ w adj1 100000
            gd x1 +/ l x2 2
            gd x3 +/ r x2 2
            gd y3 */ h 3 4
            ahXY gdRefX=adj1 minX=-2147483647 maxX=2147483647 x=x2 y=vc
            rect l t r b
            path fill=none
            M l t
            C x1 t x2 hd4 x2 vc
            C x2 y3 x3 b r b
            """,
        "curvedConnector4": """
            av adj1 val 50000
            av adj2 val 50000
            gd x2 */ w adj1 100000
            gd x1 +/ l x2 2
            gd x3 +/ r x2 2
            gd x4 +/ x2 x3 2
            gd x5 +/ x3 r 2
            gd y4 */ h adj2 100000
            gd y1 +/ t y4 2
            gd y2 +/ t y1 2
            gd y3 +/ y1 y4 2
            gd y5 +/ b y4 2
            ahXY gdRefX=adj1 minX=-2147483647 maxX=2147483647 x=x2 y=y1
            ahXY gdRefY=adj2 minY=-2147483647 maxY=2147483647 x=x3 y=y4
            rect l t r b
            path fill=none
            M l t
            C x1 t x2 y2 x2 y1
            C x2 y3 x4 y4 x3 y4
            C x5 y4 r y5 r b
            """,
        "curvedConnector5": """
            av adj1 val 50000
            av adj2 val 50000
            av adj3 val 50000
            gd x3 */ w adj1 100000
            gd x6 */ w adj3 100000
            gd x1 +/ x3 x6 2
            gd x2 +/ l x3 2
            gd x4 +/ x3 x1 2
            gd x5 +/ x6 x1 2
            gd x7 +/ x6 r 2
            gd y4 */ h adj2 100000
            gd y1 +/ t y4 2
            gd y2 +/ t y1 2
            gd y3 +/ y1 y4 2
            gd y5 +/ b y4 2
            gd y6 +/ y5 y4 2
            gd y7 +/ y5 b 2
            ahXY gdRefX=adj1 minX=-2147483647 maxX=2147483647 x=x3 y=y1
            ahXY gdRefY=adj2 minY=-2147483647 maxY=2147483647 x=x1 y=y4
            ahXY gdRefX=adj3 minX=-2147483647 maxX=2147483647 x=x6 y=y5
            rect l t r b
            path fill=none
            M l t
            C x2 t x3 y2 x3 y1
            C x3 y3 x4 y4 x1 y4
            C x5 y4 x6 y6 x6 y5
            C x6 y7 x7 b r b
            """,
        "line": """
            cxn cd4 l t
            cxn 3cd4 r b
            path
            M l t
            L r b
            """,
        "lineInv": """
            cxn cd4 l b
            cxn 3cd4 r t
            path
            M l b
            L r t
            """,
        "straightConnector1": """
            rect l t r b
            path fill=none
            M l t
            L r b
            """,
    ]
}
