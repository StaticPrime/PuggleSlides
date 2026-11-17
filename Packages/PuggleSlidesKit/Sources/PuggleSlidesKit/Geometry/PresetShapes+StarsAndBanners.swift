// DrawingML preset shapes, transcribed from ECMA-376 Part 1's presetShapeDefinitions.xml. See PresetShapeDefinition
// for the statement syntax and the errata fixed.

extension PresetShapeSource {
    static let starsAndBanners: [String: String] = [
        "doubleWave": """
            av adj1 val 6250
            av adj2 val 0
            gd a1 pin 0 adj1 12500
            gd a2 pin -10000 adj2 10000
            gd y1 */ h a1 100000
            gd dy2 */ y1 10 3
            gd y2 +- y1 0 dy2
            gd y3 +- y1 dy2 0
            gd y4 +- b 0 y1
            gd y5 +- y4 0 dy2
            gd y6 +- y4 dy2 0
            gd dx1 */ w a2 100000
            gd of2 */ w a2 50000
            gd x1 abs dx1
            gd dx2 ?: of2 0 of2
            gd x2 +- l 0 dx2
            gd dx8 ?: of2 of2 0
            gd x8 +- r 0 dx8
            gd dx3 +/ dx2 x8 6
            gd x3 +- x2 dx3 0
            gd dx4 +/ dx2 x8 3
            gd x4 +- x2 dx4 0
            gd x5 +/ x2 x8 2
            gd x6 +- x5 dx3 0
            gd x7 +/ x6 x8 2
            gd x9 +- l dx8 0
            gd x15 +- r dx2 0
            gd x10 +- x9 dx3 0
            gd x11 +- x9 dx4 0
            gd x12 +/ x9 x15 2
            gd x13 +- x12 dx3 0
            gd x14 +/ x13 x15 2
            gd x16 +- r 0 x1
            gd xAdj +- hc dx1 0
            gd il max x2 x9
            gd ir min x8 x15
            gd it */ h a1 50000
            gd ib +- b 0 it
            ahXY gdRefY=adj1 minY=0 maxY=12500 x=l y=y1
            ahXY gdRefX=adj2 minX=-10000 maxX=10000 x=xAdj y=b
            cxn cd4 x12 y1
            cxn cd2 x1 vc
            cxn 3cd4 x5 y4
            cxn 0 x16 vc
            rect il it ir ib
            path
            M x2 y1
            C x3 y2 x4 y3 x5 y1
            C x6 y2 x7 y3 x8 y1
            L x15 y4
            C x14 y6 x13 y5 x12 y4
            C x11 y6 x10 y5 x9 y4
            Z
            """,
        "ellipseRibbon": """
            av adj1 val 25000
            av adj2 val 50000
            av adj3 val 12500
            gd a1 pin 0 adj1 100000
            gd a2 pin 25000 adj2 75000
            gd q10 +- 100000 0 a1
            gd q11 */ q10 1 2
            gd q12 +- a1 0 q11
            gd minAdj3 max 0 q12
            gd a3 pin minAdj3 adj3 a1
            gd dx2 */ w a2 200000
            gd x2 +- hc 0 dx2
            gd x3 +- x2 wd8 0
            gd x4 +- r 0 x3
            gd x5 +- r 0 x2
            gd x6 +- r 0 wd8
            gd dy1 */ h a3 100000
            gd f1 */ 4 dy1 w
            gd q1 */ x3 x3 w
            gd q2 +- x3 0 q1
            gd y1 */ f1 q2 1
            gd cx1 */ x3 1 2
            gd cy1 */ f1 cx1 1
            gd cx2 +- r 0 cx1
            gd q1 */ h a1 100000
            gd dy3 +- q1 0 dy1
            gd q3 */ x2 x2 w
            gd q4 +- x2 0 q3
            gd q5 */ f1 q4 1
            gd y3 +- q5 dy3 0
            gd q6 +- dy1 dy3 y3
            gd q7 +- q6 dy1 0
            gd cy3 +- q7 dy3 0
            gd rh +- b 0 q1
            gd q8 */ dy1 14 16
            gd y2 +/ q8 rh 2
            gd y5 +- q5 rh 0
            gd y6 +- y3 rh 0
            gd cx4 */ x2 1 2
            gd q9 */ f1 cx4 1
            gd cy4 +- q9 rh 0
            gd cx5 +- r 0 cx4
            gd cy6 +- cy3 rh 0
            gd y7 +- y1 dy3 0
            gd cy7 +- q1 q1 y7
            gd y8 +- b 0 dy1
            ahXY gdRefY=adj1 minY=0 maxY=100000 x=hc y=q1
            ahXY gdRefX=adj2 minX=25000 maxX=75000 x=x2 y=b
            ahXY gdRefY=adj3 minY=minAdj3 maxY=a1 x=l y=y8
            cxn 3cd4 hc q1
            cxn cd2 wd8 y2
            cxn cd4 hc b
            cxn 0 x6 y2
            rect x2 q1 x5 y6
            path stroke=false extrusionOk=false
            M l t
            Q cx1 cy1 x3 y1
            L x2 y3
            Q hc cy3 x5 y3
            L x4 y1
            Q cx2 cy1 r t
            L x6 y2
            L r rh
            Q cx5 cy4 x5 y5
            L x5 y6
            Q hc cy6 x2 y6
            L x2 y5
            Q cx4 cy4 l rh
            L wd8 y2
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M x3 y7
            L x3 y1
            L x2 y3
            Q hc cy3 x5 y3
            L x4 y1
            L x4 y7
            Q hc cy7 x3 y7
            Z
            path fill=none extrusionOk=false
            M l t
            Q cx1 cy1 x3 y1
            L x2 y3
            Q hc cy3 x5 y3
            L x4 y1
            Q cx2 cy1 r t
            L x6 y2
            L r rh
            Q cx5 cy4 x5 y5
            L x5 y6
            Q hc cy6 x2 y6
            L x2 y5
            Q cx4 cy4 l rh
            L wd8 y2
            Z
            M x2 y5
            L x2 y3
            M x5 y3
            L x5 y5
            M x3 y1
            L x3 y7
            M x4 y7
            L x4 y1
            """,
        "ellipseRibbon2": """
            av adj1 val 25000
            av adj2 val 50000
            av adj3 val 12500
            gd a1 pin 0 adj1 100000
            gd a2 pin 25000 adj2 75000
            gd q10 +- 100000 0 a1
            gd q11 */ q10 1 2
            gd q12 +- a1 0 q11
            gd minAdj3 max 0 q12
            gd a3 pin minAdj3 adj3 a1
            gd dx2 */ w a2 200000
            gd x2 +- hc 0 dx2
            gd x3 +- x2 wd8 0
            gd x4 +- r 0 x3
            gd x5 +- r 0 x2
            gd x6 +- r 0 wd8
            gd dy1 */ h a3 100000
            gd f1 */ 4 dy1 w
            gd q1 */ x3 x3 w
            gd q2 +- x3 0 q1
            gd u1 */ f1 q2 1
            gd y1 +- b 0 u1
            gd cx1 */ x3 1 2
            gd cu1 */ f1 cx1 1
            gd cy1 +- b 0 cu1
            gd cx2 +- r 0 cx1
            gd q1 */ h a1 100000
            gd dy3 +- q1 0 dy1
            gd q3 */ x2 x2 w
            gd q4 +- x2 0 q3
            gd q5 */ f1 q4 1
            gd u3 +- q5 dy3 0
            gd y3 +- b 0 u3
            gd q6 +- dy1 dy3 u3
            gd q7 +- q6 dy1 0
            gd cu3 +- q7 dy3 0
            gd cy3 +- b 0 cu3
            gd rh +- b 0 q1
            gd q8 */ dy1 14 16
            gd u2 +/ q8 rh 2
            gd y2 +- b 0 u2
            gd u5 +- q5 rh 0
            gd y5 +- b 0 u5
            gd u6 +- u3 rh 0
            gd y6 +- b 0 u6
            gd cx4 */ x2 1 2
            gd q9 */ f1 cx4 1
            gd cu4 +- q9 rh 0
            gd cy4 +- b 0 cu4
            gd cx5 +- r 0 cx4
            gd cu6 +- cu3 rh 0
            gd cy6 +- b 0 cu6
            gd u7 +- u1 dy3 0
            gd y7 +- b 0 u7
            gd cu7 +- q1 q1 u7
            gd cy7 +- b 0 cu7
            ahXY gdRefY=adj1 minY=0 maxY=100000 x=hc y=rh
            ahXY gdRefX=adj2 minX=25000 maxX=100000 x=x2 y=t
            ahXY gdRefY=adj3 minY=minAdj3 maxY=a1 x=l y=dy1
            cxn 3cd4 hc t
            cxn cd2 wd8 y2
            cxn cd4 hc rh
            cxn 0 x6 y2
            rect x2 y6 x5 rh
            path stroke=false extrusionOk=false
            M l b
            Q cx1 cy1 x3 y1
            L x2 y3
            Q hc cy3 x5 y3
            L x4 y1
            Q cx2 cy1 r b
            L x6 y2
            L r q1
            Q cx5 cy4 x5 y5
            L x5 y6
            Q hc cy6 x2 y6
            L x2 y5
            Q cx4 cy4 l q1
            L wd8 y2
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M x3 y7
            L x3 y1
            L x2 y3
            Q hc cy3 x5 y3
            L x4 y1
            L x4 y7
            Q hc cy7 x3 y7
            Z
            path fill=none extrusionOk=false
            M l b
            L wd8 y2
            L l q1
            Q cx4 cy4 x2 y5
            L x2 y6
            Q hc cy6 x5 y6
            L x5 y5
            Q cx5 cy4 r q1
            L x6 y2
            L r b
            Q cx2 cy1 x4 y1
            L x5 y3
            Q hc cy3 x2 y3
            L x3 y1
            Q cx1 cy1 l b
            Z
            M x2 y3
            L x2 y5
            M x5 y5
            L x5 y3
            M x3 y7
            L x3 y1
            M x4 y1
            L x4 y7
            """,
        "horizontalScroll": """
            av adj val 12500
            gd a pin 0 adj 25000
            gd ch */ ss a 100000
            gd ch2 */ ch 1 2
            gd ch4 */ ch 1 4
            gd y3 +- ch ch2 0
            gd y4 +- ch ch 0
            gd y6 +- b 0 ch
            gd y7 +- b 0 ch2
            gd y5 +- y6 0 ch2
            gd x3 +- r 0 ch
            gd x4 +- r 0 ch2
            ahXY gdRefX=adj minX=0 maxX=25000 x=ch y=t
            cxn cd4 hc ch
            cxn cd2 l vc
            cxn 3cd4 hc y6
            cxn 0 r vc
            rect ch ch x4 y6
            path stroke=false extrusionOk=false
            M r ch2
            A ch2 ch2 0 cd4
            L x4 ch2
            A ch4 ch4 0 cd2
            L x3 ch
            L ch2 ch
            A ch2 ch2 3cd4 -5400000
            L l y7
            A ch2 ch2 cd2 -10800000
            L ch y6
            L x4 y6
            A ch2 ch2 cd4 -5400000
            Z
            M ch2 y4
            A ch2 ch2 cd4 -5400000
            A ch4 ch4 0 -10800000
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M ch2 y4
            A ch2 ch2 cd4 -5400000
            A ch4 ch4 0 -10800000
            Z
            M x4 ch
            A ch2 ch2 cd4 -16200000
            A ch4 ch4 cd2 -10800000
            Z
            path fill=none extrusionOk=false
            M l y3
            A ch2 ch2 cd2 cd4
            L x3 ch
            L x3 ch2
            A ch2 ch2 cd2 cd2
            L r y5
            A ch2 ch2 0 cd4
            L ch y6
            L ch y7
            A ch2 ch2 0 cd2
            Z
            M x3 ch
            L x4 ch
            A ch2 ch2 cd4 -5400000
            M x4 ch
            L x4 ch2
            A ch4 ch4 0 cd2
            M ch2 y4
            L ch2 y3
            A ch4 ch4 cd2 cd2
            A ch2 ch2 0 cd2
            M ch y3
            L ch y6
            """,
        "irregularSeal1": """
            gd x5 */ w 4627 21600
            gd x12 */ w 8485 21600
            gd x21 */ w 16702 21600
            gd x24 */ w 14522 21600
            gd y3 */ h 6320 21600
            gd y6 */ h 8615 21600
            gd y9 */ h 13937 21600
            gd y18 */ h 13290 21600
            cxn 3cd4 x24 t
            cxn cd2 l y6
            cxn cd4 x12 b
            cxn 0 r y18
            rect x5 y3 x21 y9
            path w=21600 h=21600
            M 10800 5800
            L 14522 0
            L 14155 5325
            L 18380 4457
            L 16702 7315
            L 21097 8137
            L 17607 10475
            L 21600 13290
            L 16837 12942
            L 18145 18095
            L 14020 14457
            L 13247 19737
            L 10532 14935
            L 8485 21600
            L 7715 15627
            L 4762 17617
            L 5667 13937
            L 135 14587
            L 3722 11775
            L 0 8615
            L 4627 7617
            L 370 2295
            L 7312 6320
            L 8352 2295
            Z
            """,
        "irregularSeal2": """
            gd x2 */ w 9722 21600
            gd x5 */ w 5372 21600
            gd x16 */ w 11612 21600
            gd x19 */ w 14640 21600
            gd y2 */ h 1887 21600
            gd y3 */ h 6382 21600
            gd y8 */ h 12877 21600
            gd y14 */ h 19712 21600
            gd y16 */ h 18842 21600
            gd y17 */ h 15935 21600
            gd y24 */ h 6645 21600
            cxn 3cd4 x2 y2
            cxn cd2 l y8
            cxn cd4 x16 y16
            cxn 0 r y24
            rect x5 y3 x19 y17
            path w=21600 h=21600
            M 11462 4342
            L 14790 0
            L 14525 5777
            L 18007 3172
            L 16380 6532
            L 21600 6645
            L 16985 9402
            L 18270 11290
            L 16380 12310
            L 18877 15632
            L 14640 14350
            L 14942 17370
            L 12180 15935
            L 11612 18842
            L 9872 17370
            L 8700 19712
            L 7527 18125
            L 4917 21600
            L 4805 18240
            L 1285 17825
            L 3330 15370
            L 0 12877
            L 3935 11592
            L 1172 8270
            L 5372 7817
            L 4502 3625
            L 8550 6382
            L 9722 1887
            Z
            """,
        "leftRightRibbon": """
            av adj1 val 50000
            av adj2 val 50000
            av adj3 val 16667
            gd a3 pin 0 adj3 33333
            gd maxAdj1 +- 100000 0 a3
            gd a1 pin 0 adj1 maxAdj1
            gd w1 +- wd2 0 wd32
            gd maxAdj2 */ 100000 w1 ss
            gd a2 pin 0 adj2 maxAdj2
            gd x1 */ ss a2 100000
            gd x4 +- r 0 x1
            gd dy1 */ h a1 200000
            gd dy2 */ h a3 -200000
            gd ly1 +- vc dy2 dy1
            gd ry4 +- vc dy1 dy2
            gd ly2 +- ly1 dy1 0
            gd ry3 +- b 0 ly2
            gd ly4 */ ly2 2 1
            gd ry1 +- b 0 ly4
            gd ly3 +- ly4 0 ly1
            gd ry2 +- b 0 ly3
            gd hR */ a3 ss 400000
            gd x2 +- hc 0 wd32
            gd x3 +- hc wd32 0
            gd y1 +- ly1 hR 0
            gd y2 +- ry2 0 hR
            ahXY gdRefY=adj1 minY=0 maxY=maxAdj1 x=x4 y=ry2
            ahXY gdRefX=adj2 minX=0 maxX=maxAdj2 x=x1 y=t
            ahXY gdRefY=adj3 minY=0 maxY=33333 x=x3 y=ry2
            cxn 0 r ry3
            cxn cd4 x4 b
            cxn cd4 x1 ly4
            cxn cd2 l ly2
            cxn 3cd4 x1 t
            cxn 3cd4 x4 ry1
            rect x1 ly1 x4 ry4
            path stroke=false extrusionOk=false
            M l ly2
            L x1 t
            L x1 ly1
            L hc ly1
            A wd32 hR 3cd4 cd2
            A wd32 hR 3cd4 -10800000
            L x4 ry2
            L x4 ry1
            L r ry3
            L x4 b
            L x4 ry4
            L hc ry4
            A wd32 hR cd4 cd4
            L x2 ly3
            L x1 ly3
            L x1 ly4
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M x3 y1
            A wd32 hR 0 cd4
            A wd32 hR 3cd4 -10800000
            L x3 ry2
            Z
            path fill=none extrusionOk=false
            M l ly2
            L x1 t
            L x1 ly1
            L hc ly1
            A wd32 hR 3cd4 cd2
            A wd32 hR 3cd4 -10800000
            L x4 ry2
            L x4 ry1
            L r ry3
            L x4 b
            L x4 ry4
            L hc ry4
            A wd32 hR cd4 cd4
            L x2 ly3
            L x1 ly3
            L x1 ly4
            Z
            M x3 y1
            L x3 ry2
            M x2 y2
            L x2 ly3
            """,
        "ribbon": """
            av adj1 val 16667
            av adj2 val 50000
            gd a1 pin 0 adj1 33333
            gd a2 pin 25000 adj2 75000
            gd x10 +- r 0 wd8
            gd dx2 */ w a2 200000
            gd x2 +- hc 0 dx2
            gd x9 +- hc dx2 0
            gd x3 +- x2 wd32 0
            gd x8 +- x9 0 wd32
            gd x5 +- x2 wd8 0
            gd x6 +- x9 0 wd8
            gd x4 +- x5 0 wd32
            gd x7 +- x6 wd32 0
            gd y1 */ h a1 200000
            gd y2 */ h a1 100000
            gd y4 +- b 0 y2
            gd y3 */ y4 1 2
            gd hR */ h a1 400000
            gd y5 +- b 0 hR
            gd y6 +- y2 0 hR
            ahXY gdRefY=adj1 minY=0 maxY=33333 x=hc y=y2
            ahXY gdRefX=adj2 minX=25000 maxX=75000 x=x2 y=t
            cxn 3cd4 hc y2
            cxn cd2 wd8 y3
            cxn cd4 hc b
            cxn 0 x10 y3
            rect x2 y2 x9 b
            path stroke=false extrusionOk=false
            M l t
            L x4 t
            A wd32 hR 3cd4 cd2
            L x3 y1
            A wd32 hR 3cd4 -10800000
            L x8 y2
            A wd32 hR cd4 -10800000
            L x7 y1
            A wd32 hR cd4 cd2
            L r t
            L x10 y3
            L r y4
            L x9 y4
            L x9 y5
            A wd32 hR 0 cd4
            L x3 b
            A wd32 hR cd4 cd4
            L x2 y4
            L l y4
            L wd8 y3
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M x5 hR
            A wd32 hR 0 cd4
            L x3 y1
            A wd32 hR 3cd4 -10800000
            L x5 y2
            Z
            M x6 hR
            A wd32 hR cd2 -5400000
            L x8 y1
            A wd32 hR 3cd4 cd2
            L x6 y2
            Z
            path fill=none extrusionOk=false
            M l t
            L x4 t
            A wd32 hR 3cd4 cd2
            L x3 y1
            A wd32 hR 3cd4 -10800000
            L x8 y2
            A wd32 hR cd4 -10800000
            L x7 y1
            A wd32 hR cd4 cd2
            L r t
            L x10 y3
            L r y4
            L x9 y4
            L x9 y5
            A wd32 hR 0 cd4
            L x3 b
            A wd32 hR cd4 cd4
            L x2 y4
            L l y4
            L wd8 y3
            Z
            M x5 hR
            L x5 y2
            M x6 y2
            L x6 hR
            M x2 y4
            L x2 y6
            M x9 y6
            L x9 y4
            """,
        "ribbon2": """
            av adj1 val 16667
            av adj2 val 50000
            gd a1 pin 0 adj1 33333
            gd a2 pin 25000 adj2 75000
            gd x10 +- r 0 wd8
            gd dx2 */ w a2 200000
            gd x2 +- hc 0 dx2
            gd x9 +- hc dx2 0
            gd x3 +- x2 wd32 0
            gd x8 +- x9 0 wd32
            gd x5 +- x2 wd8 0
            gd x6 +- x9 0 wd8
            gd x4 +- x5 0 wd32
            gd x7 +- x6 wd32 0
            gd dy1 */ h a1 200000
            gd y1 +- b 0 dy1
            gd dy2 */ h a1 100000
            gd y2 +- b 0 dy2
            gd y4 +- t dy2 0
            gd y3 +/ y4 b 2
            gd hR */ h a1 400000
            gd y6 +- b 0 hR
            gd y7 +- y1 0 hR
            ahXY gdRefY=adj1 minY=0 maxY=33333 x=hc y=y2
            ahXY gdRefX=adj2 minX=25000 maxX=75000 x=x2 y=b
            cxn 3cd4 hc t
            cxn cd2 wd8 y3
            cxn cd4 hc y2
            cxn 0 x10 y3
            rect x2 t x9 y2
            path stroke=false extrusionOk=false
            M l b
            L x4 b
            A wd32 hR cd4 -10800000
            L x3 y1
            A wd32 hR cd4 cd2
            L x8 y2
            A wd32 hR 3cd4 cd2
            L x7 y1
            A wd32 hR 3cd4 -10800000
            L r b
            L x10 y3
            L r y4
            L x9 y4
            L x9 hR
            A wd32 hR 0 -5400000
            L x3 t
            A wd32 hR 3cd4 -5400000
            L x2 y4
            L l y4
            L wd8 y3
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M x5 y6
            A wd32 hR 0 -5400000
            L x3 y1
            A wd32 hR cd4 cd2
            L x5 y2
            Z
            M x6 y6
            A wd32 hR cd2 cd4
            L x8 y1
            A wd32 hR cd4 -10800000
            L x6 y2
            Z
            path fill=none extrusionOk=false
            M l b
            L wd8 y3
            L l y4
            L x2 y4
            L x2 hR
            A wd32 hR cd2 cd4
            L x8 t
            A wd32 hR 3cd4 cd4
            L x9 y4
            L x9 y4
            L r y4
            L x10 y3
            L r b
            L x7 b
            A wd32 hR cd4 cd2
            L x8 y1
            A wd32 hR cd4 -10800000
            L x3 y2
            A wd32 hR 3cd4 -10800000
            L x4 y1
            A wd32 hR 3cd4 cd2
            Z
            M x5 y2
            L x5 y6
            M x6 y6
            L x6 y2
            M x2 y7
            L x2 y4
            M x9 y4
            L x9 y7
            """,
        "star10": """
            av adj val 42533
            av hf val 105146
            gd a pin 0 adj 50000
            gd swd2 */ wd2 hf 100000
            gd dx1 */ swd2 95106 100000
            gd dx2 */ swd2 58779 100000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc dx2 0
            gd x4 +- hc dx1 0
            gd dy1 */ hd2 80902 100000
            gd dy2 */ hd2 30902 100000
            gd y1 +- vc 0 dy1
            gd y2 +- vc 0 dy2
            gd y3 +- vc dy2 0
            gd y4 +- vc dy1 0
            gd iwd2 */ swd2 a 50000
            gd ihd2 */ hd2 a 50000
            gd sdx1 */ iwd2 80902 100000
            gd sdx2 */ iwd2 30902 100000
            gd sdy1 */ ihd2 95106 100000
            gd sdy2 */ ihd2 58779 100000
            gd sx1 +- hc 0 iwd2
            gd sx2 +- hc 0 sdx1
            gd sx3 +- hc 0 sdx2
            gd sx4 +- hc sdx2 0
            gd sx5 +- hc sdx1 0
            gd sx6 +- hc iwd2 0
            gd sy1 +- vc 0 sdy1
            gd sy2 +- vc 0 sdy2
            gd sy3 +- vc sdy2 0
            gd sy4 +- vc sdy1 0
            gd yAdj +- vc 0 ihd2
            ahXY gdRefY=adj minY=0 maxY=50000 x=hc y=yAdj
            cxn 0 x4 y2
            cxn 0 x4 y3
            cxn cd4 x3 y4
            cxn cd4 hc b
            cxn cd4 x2 y4
            cxn cd2 x1 y3
            cxn cd2 x1 y2
            cxn 3cd4 x2 y1
            cxn 3cd4 hc t
            cxn 3cd4 x3 y1
            rect sx2 sy2 sx5 sy3
            path
            M x1 y2
            L sx2 sy2
            L x2 y1
            L sx3 sy1
            L hc t
            L sx4 sy1
            L x3 y1
            L sx5 sy2
            L x4 y2
            L sx6 vc
            L x4 y3
            L sx5 sy3
            L x3 y4
            L sx4 sy4
            L hc b
            L sx3 sy4
            L x2 y4
            L sx2 sy3
            L x1 y3
            L sx1 vc
            Z
            """,
        "star12": """
            av adj val 37500
            gd a pin 0 adj 50000
            gd dx1 cos wd2 1800000
            gd dy1 sin hd2 3600000
            gd x1 +- hc 0 dx1
            gd x3 */ w 3 4
            gd x4 +- hc dx1 0
            gd y1 +- vc 0 dy1
            gd y3 */ h 3 4
            gd y4 +- vc dy1 0
            gd iwd2 */ wd2 a 50000
            gd ihd2 */ hd2 a 50000
            gd sdx1 cos iwd2 900000
            gd sdx2 cos iwd2 2700000
            gd sdx3 cos iwd2 4500000
            gd sdy1 sin ihd2 4500000
            gd sdy2 sin ihd2 2700000
            gd sdy3 sin ihd2 900000
            gd sx1 +- hc 0 sdx1
            gd sx2 +- hc 0 sdx2
            gd sx3 +- hc 0 sdx3
            gd sx4 +- hc sdx3 0
            gd sx5 +- hc sdx2 0
            gd sx6 +- hc sdx1 0
            gd sy1 +- vc 0 sdy1
            gd sy2 +- vc 0 sdy2
            gd sy3 +- vc 0 sdy3
            gd sy4 +- vc sdy3 0
            gd sy5 +- vc sdy2 0
            gd sy6 +- vc sdy1 0
            gd yAdj +- vc 0 ihd2
            ahXY gdRefY=adj minY=0 maxY=50000 x=hc y=yAdj
            cxn 0 x4 hd4
            cxn 0 r vc
            cxn 0 x4 y3
            cxn cd4 x3 y4
            cxn cd4 hc b
            cxn cd4 wd4 y4
            cxn cd2 x1 y3
            cxn cd2 l vc
            cxn cd2 x1 hd4
            cxn 3cd4 wd4 y1
            cxn 3cd4 hc t
            cxn 3cd4 x3 y1
            rect sx2 sy2 sx5 sy5
            path
            M l vc
            L sx1 sy3
            L x1 hd4
            L sx2 sy2
            L wd4 y1
            L sx3 sy1
            L hc t
            L sx4 sy1
            L x3 y1
            L sx5 sy2
            L x4 hd4
            L sx6 sy3
            L r vc
            L sx6 sy4
            L x4 y3
            L sx5 sy5
            L x3 y4
            L sx4 sy6
            L hc b
            L sx3 sy6
            L wd4 y4
            L sx2 sy5
            L x1 y3
            L sx1 sy4
            Z
            """,
        "star16": """
            av adj val 37500
            gd a pin 0 adj 50000
            gd dx1 */ wd2 92388 100000
            gd dx2 */ wd2 70711 100000
            gd dx3 */ wd2 38268 100000
            gd dy1 */ hd2 92388 100000
            gd dy2 */ hd2 70711 100000
            gd dy3 */ hd2 38268 100000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc 0 dx3
            gd x4 +- hc dx3 0
            gd x5 +- hc dx2 0
            gd x6 +- hc dx1 0
            gd y1 +- vc 0 dy1
            gd y2 +- vc 0 dy2
            gd y3 +- vc 0 dy3
            gd y4 +- vc dy3 0
            gd y5 +- vc dy2 0
            gd y6 +- vc dy1 0
            gd iwd2 */ wd2 a 50000
            gd ihd2 */ hd2 a 50000
            gd sdx1 */ iwd2 98079 100000
            gd sdx2 */ iwd2 83147 100000
            gd sdx3 */ iwd2 55557 100000
            gd sdx4 */ iwd2 19509 100000
            gd sdy1 */ ihd2 98079 100000
            gd sdy2 */ ihd2 83147 100000
            gd sdy3 */ ihd2 55557 100000
            gd sdy4 */ ihd2 19509 100000
            gd sx1 +- hc 0 sdx1
            gd sx2 +- hc 0 sdx2
            gd sx3 +- hc 0 sdx3
            gd sx4 +- hc 0 sdx4
            gd sx5 +- hc sdx4 0
            gd sx6 +- hc sdx3 0
            gd sx7 +- hc sdx2 0
            gd sx8 +- hc sdx1 0
            gd sy1 +- vc 0 sdy1
            gd sy2 +- vc 0 sdy2
            gd sy3 +- vc 0 sdy3
            gd sy4 +- vc 0 sdy4
            gd sy5 +- vc sdy4 0
            gd sy6 +- vc sdy3 0
            gd sy7 +- vc sdy2 0
            gd sy8 +- vc sdy1 0
            gd idx cos iwd2 2700000
            gd idy sin ihd2 2700000
            gd il +- hc 0 idx
            gd it +- vc 0 idy
            gd ir +- hc idx 0
            gd ib +- vc idy 0
            gd yAdj +- vc 0 ihd2
            ahXY gdRefY=adj minY=0 maxY=50000 x=hc y=yAdj
            cxn 0 x5 y2
            cxn 0 x6 y3
            cxn 0 r vc
            cxn 0 x6 y4
            cxn 0 x5 y5
            cxn cd4 x4 y6
            cxn cd4 hc b
            cxn cd4 x3 y6
            cxn cd2 x2 y5
            cxn cd2 x1 y4
            cxn cd2 l vc
            cxn cd2 x1 y3
            cxn cd2 x2 y2
            cxn 3cd4 x3 y1
            cxn 3cd4 hc t
            cxn 3cd4 x4 y1
            rect il it ir ib
            path
            M l vc
            L sx1 sy4
            L x1 y3
            L sx2 sy3
            L x2 y2
            L sx3 sy2
            L x3 y1
            L sx4 sy1
            L hc t
            L sx5 sy1
            L x4 y1
            L sx6 sy2
            L x5 y2
            L sx7 sy3
            L x6 y3
            L sx8 sy4
            L r vc
            L sx8 sy5
            L x6 y4
            L sx7 sy6
            L x5 y5
            L sx6 sy7
            L x4 y6
            L sx5 sy8
            L hc b
            L sx4 sy8
            L x3 y6
            L sx3 sy7
            L x2 y5
            L sx2 sy6
            L x1 y4
            L sx1 sy5
            Z
            """,
        "star24": """
            av adj val 37500
            gd a pin 0 adj 50000
            gd dx1 cos wd2 900000
            gd dx2 cos wd2 1800000
            gd dx3 cos wd2 2700000
            gd dx4 val wd4
            gd dx5 cos wd2 4500000
            gd dy1 sin hd2 4500000
            gd dy2 sin hd2 3600000
            gd dy3 sin hd2 2700000
            gd dy4 val hd4
            gd dy5 sin hd2 900000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc 0 dx3
            gd x4 +- hc 0 dx4
            gd x5 +- hc 0 dx5
            gd x6 +- hc dx5 0
            gd x7 +- hc dx4 0
            gd x8 +- hc dx3 0
            gd x9 +- hc dx2 0
            gd x10 +- hc dx1 0
            gd y1 +- vc 0 dy1
            gd y2 +- vc 0 dy2
            gd y3 +- vc 0 dy3
            gd y4 +- vc 0 dy4
            gd y5 +- vc 0 dy5
            gd y6 +- vc dy5 0
            gd y7 +- vc dy4 0
            gd y8 +- vc dy3 0
            gd y9 +- vc dy2 0
            gd y10 +- vc dy1 0
            gd iwd2 */ wd2 a 50000
            gd ihd2 */ hd2 a 50000
            gd sdx1 */ iwd2 99144 100000
            gd sdx2 */ iwd2 92388 100000
            gd sdx3 */ iwd2 79335 100000
            gd sdx4 */ iwd2 60876 100000
            gd sdx5 */ iwd2 38268 100000
            gd sdx6 */ iwd2 13053 100000
            gd sdy1 */ ihd2 99144 100000
            gd sdy2 */ ihd2 92388 100000
            gd sdy3 */ ihd2 79335 100000
            gd sdy4 */ ihd2 60876 100000
            gd sdy5 */ ihd2 38268 100000
            gd sdy6 */ ihd2 13053 100000
            gd sx1 +- hc 0 sdx1
            gd sx2 +- hc 0 sdx2
            gd sx3 +- hc 0 sdx3
            gd sx4 +- hc 0 sdx4
            gd sx5 +- hc 0 sdx5
            gd sx6 +- hc 0 sdx6
            gd sx7 +- hc sdx6 0
            gd sx8 +- hc sdx5 0
            gd sx9 +- hc sdx4 0
            gd sx10 +- hc sdx3 0
            gd sx11 +- hc sdx2 0
            gd sx12 +- hc sdx1 0
            gd sy1 +- vc 0 sdy1
            gd sy2 +- vc 0 sdy2
            gd sy3 +- vc 0 sdy3
            gd sy4 +- vc 0 sdy4
            gd sy5 +- vc 0 sdy5
            gd sy6 +- vc 0 sdy6
            gd sy7 +- vc sdy6 0
            gd sy8 +- vc sdy5 0
            gd sy9 +- vc sdy4 0
            gd sy10 +- vc sdy3 0
            gd sy11 +- vc sdy2 0
            gd sy12 +- vc sdy1 0
            gd idx cos iwd2 2700000
            gd idy sin ihd2 2700000
            gd il +- hc 0 idx
            gd it +- vc 0 idy
            gd ir +- hc idx 0
            gd ib +- vc idy 0
            gd yAdj +- vc 0 ihd2
            ahXY gdRefY=adj minY=0 maxY=50000 x=hc y=yAdj
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il it ir ib
            path
            M l vc
            L sx1 sy6
            L x1 y5
            L sx2 sy5
            L x2 y4
            L sx3 sy4
            L x3 y3
            L sx4 sy3
            L x4 y2
            L sx5 sy2
            L x5 y1
            L sx6 sy1
            L hc t
            L sx7 sy1
            L x6 y1
            L sx8 sy2
            L x7 y2
            L sx9 sy3
            L x8 y3
            L sx10 sy4
            L x9 y4
            L sx11 sy5
            L x10 y5
            L sx12 sy6
            L r vc
            L sx12 sy7
            L x10 y6
            L sx11 sy8
            L x9 y7
            L sx10 sy9
            L x8 y8
            L sx9 sy10
            L x7 y9
            L sx8 sy11
            L x6 y10
            L sx7 sy12
            L hc b
            L sx6 sy12
            L x5 y10
            L sx5 sy11
            L x4 y9
            L sx4 sy10
            L x3 y8
            L sx3 sy9
            L x2 y7
            L sx2 sy8
            L x1 y6
            L sx1 sy7
            Z
            """,
        "star32": """
            av adj val 37500
            gd a pin 0 adj 50000
            gd dx1 */ wd2 98079 100000
            gd dx2 */ wd2 92388 100000
            gd dx3 */ wd2 83147 100000
            gd dx4 cos wd2 2700000
            gd dx5 */ wd2 55557 100000
            gd dx6 */ wd2 38268 100000
            gd dx7 */ wd2 19509 100000
            gd dy1 */ hd2 98079 100000
            gd dy2 */ hd2 92388 100000
            gd dy3 */ hd2 83147 100000
            gd dy4 sin hd2 2700000
            gd dy5 */ hd2 55557 100000
            gd dy6 */ hd2 38268 100000
            gd dy7 */ hd2 19509 100000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc 0 dx3
            gd x4 +- hc 0 dx4
            gd x5 +- hc 0 dx5
            gd x6 +- hc 0 dx6
            gd x7 +- hc 0 dx7
            gd x8 +- hc dx7 0
            gd x9 +- hc dx6 0
            gd x10 +- hc dx5 0
            gd x11 +- hc dx4 0
            gd x12 +- hc dx3 0
            gd x13 +- hc dx2 0
            gd x14 +- hc dx1 0
            gd y1 +- vc 0 dy1
            gd y2 +- vc 0 dy2
            gd y3 +- vc 0 dy3
            gd y4 +- vc 0 dy4
            gd y5 +- vc 0 dy5
            gd y6 +- vc 0 dy6
            gd y7 +- vc 0 dy7
            gd y8 +- vc dy7 0
            gd y9 +- vc dy6 0
            gd y10 +- vc dy5 0
            gd y11 +- vc dy4 0
            gd y12 +- vc dy3 0
            gd y13 +- vc dy2 0
            gd y14 +- vc dy1 0
            gd iwd2 */ wd2 a 50000
            gd ihd2 */ hd2 a 50000
            gd sdx1 */ iwd2 99518 100000
            gd sdx2 */ iwd2 95694 100000
            gd sdx3 */ iwd2 88192 100000
            gd sdx4 */ iwd2 77301 100000
            gd sdx5 */ iwd2 63439 100000
            gd sdx6 */ iwd2 47140 100000
            gd sdx7 */ iwd2 29028 100000
            gd sdx8 */ iwd2 9802 100000
            gd sdy1 */ ihd2 99518 100000
            gd sdy2 */ ihd2 95694 100000
            gd sdy3 */ ihd2 88192 100000
            gd sdy4 */ ihd2 77301 100000
            gd sdy5 */ ihd2 63439 100000
            gd sdy6 */ ihd2 47140 100000
            gd sdy7 */ ihd2 29028 100000
            gd sdy8 */ ihd2 9802 100000
            gd sx1 +- hc 0 sdx1
            gd sx2 +- hc 0 sdx2
            gd sx3 +- hc 0 sdx3
            gd sx4 +- hc 0 sdx4
            gd sx5 +- hc 0 sdx5
            gd sx6 +- hc 0 sdx6
            gd sx7 +- hc 0 sdx7
            gd sx8 +- hc 0 sdx8
            gd sx9 +- hc sdx8 0
            gd sx10 +- hc sdx7 0
            gd sx11 +- hc sdx6 0
            gd sx12 +- hc sdx5 0
            gd sx13 +- hc sdx4 0
            gd sx14 +- hc sdx3 0
            gd sx15 +- hc sdx2 0
            gd sx16 +- hc sdx1 0
            gd sy1 +- vc 0 sdy1
            gd sy2 +- vc 0 sdy2
            gd sy3 +- vc 0 sdy3
            gd sy4 +- vc 0 sdy4
            gd sy5 +- vc 0 sdy5
            gd sy6 +- vc 0 sdy6
            gd sy7 +- vc 0 sdy7
            gd sy8 +- vc 0 sdy8
            gd sy9 +- vc sdy8 0
            gd sy10 +- vc sdy7 0
            gd sy11 +- vc sdy6 0
            gd sy12 +- vc sdy5 0
            gd sy13 +- vc sdy4 0
            gd sy14 +- vc sdy3 0
            gd sy15 +- vc sdy2 0
            gd sy16 +- vc sdy1 0
            gd idx cos iwd2 2700000
            gd idy sin ihd2 2700000
            gd il +- hc 0 idx
            gd it +- vc 0 idy
            gd ir +- hc idx 0
            gd ib +- vc idy 0
            gd yAdj +- vc 0 ihd2
            ahXY gdRefY=adj minY=0 maxY=50000 x=hc y=yAdj
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect il it ir ib
            path
            M l vc
            L sx1 sy8
            L x1 y7
            L sx2 sy7
            L x2 y6
            L sx3 sy6
            L x3 y5
            L sx4 sy5
            L x4 y4
            L sx5 sy4
            L x5 y3
            L sx6 sy3
            L x6 y2
            L sx7 sy2
            L x7 y1
            L sx8 sy1
            L hc t
            L sx9 sy1
            L x8 y1
            L sx10 sy2
            L x9 y2
            L sx11 sy3
            L x10 y3
            L sx12 sy4
            L x11 y4
            L sx13 sy5
            L x12 y5
            L sx14 sy6
            L x13 y6
            L sx15 sy7
            L x14 y7
            L sx16 sy8
            L r vc
            L sx16 sy9
            L x14 y8
            L sx15 sy10
            L x13 y9
            L sx14 sy11
            L x12 y10
            L sx13 sy12
            L x11 y11
            L sx12 sy13
            L x10 y12
            L sx11 sy14
            L x9 y13
            L sx10 sy15
            L x8 y14
            L sx9 sy16
            L hc b
            L sx8 sy16
            L x7 y14
            L sx7 sy15
            L x6 y13
            L sx6 sy14
            L x5 y12
            L sx5 sy13
            L x4 y11
            L sx4 sy12
            L x3 y10
            L sx3 sy11
            L x2 y9
            L sx2 sy10
            L x1 y8
            L sx1 sy9
            Z
            """,
        "star4": """
            av adj val 12500
            gd a pin 0 adj 50000
            gd iwd2 */ wd2 a 50000
            gd ihd2 */ hd2 a 50000
            gd sdx cos iwd2 2700000
            gd sdy sin ihd2 2700000
            gd sx1 +- hc 0 sdx
            gd sx2 +- hc sdx 0
            gd sy1 +- vc 0 sdy
            gd sy2 +- vc sdy 0
            gd yAdj +- vc 0 ihd2
            ahXY gdRefY=adj minY=0 maxY=50000 x=hc y=yAdj
            cxn 3cd4 hc t
            cxn cd2 l vc
            cxn cd4 hc b
            cxn 0 r vc
            rect sx1 sy1 sx2 sy2
            path
            M l vc
            L sx1 sy1
            L hc t
            L sx2 sy1
            L r vc
            L sx2 sy2
            L hc b
            L sx1 sy2
            Z
            """,
        "star5": """
            av adj val 19098
            av hf val 105146
            av vf val 110557
            gd a pin 0 adj 50000
            gd swd2 */ wd2 hf 100000
            gd shd2 */ hd2 vf 100000
            gd svc */ vc vf 100000
            gd dx1 cos swd2 1080000
            gd dx2 cos swd2 18360000
            gd dy1 sin shd2 1080000
            gd dy2 sin shd2 18360000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc dx2 0
            gd x4 +- hc dx1 0
            gd y1 +- svc 0 dy1
            gd y2 +- svc 0 dy2
            gd iwd2 */ swd2 a 50000
            gd ihd2 */ shd2 a 50000
            gd sdx1 cos iwd2 20520000
            gd sdx2 cos iwd2 3240000
            gd sdy1 sin ihd2 3240000
            gd sdy2 sin ihd2 20520000
            gd sx1 +- hc 0 sdx1
            gd sx2 +- hc 0 sdx2
            gd sx3 +- hc sdx2 0
            gd sx4 +- hc sdx1 0
            gd sy1 +- svc 0 sdy1
            gd sy2 +- svc 0 sdy2
            gd sy3 +- svc ihd2 0
            gd yAdj +- svc 0 ihd2
            ahXY gdRefY=adj minY=0 maxY=50000 x=hc y=yAdj
            cxn 3cd4 hc t
            cxn cd2 x1 y1
            cxn cd4 x2 y2
            cxn cd4 x3 y2
            cxn 0 x4 y1
            rect sx1 sy1 sx4 sy3
            path
            M x1 y1
            L sx2 sy1
            L hc t
            L sx3 sy1
            L x4 y1
            L sx4 sy2
            L x3 y2
            L hc sy3
            L x2 y2
            L sx1 sy2
            Z
            """,
        "star6": """
            av adj val 28868
            av hf val 115470
            gd a pin 0 adj 50000
            gd swd2 */ wd2 hf 100000
            gd dx1 cos swd2 1800000
            gd x1 +- hc 0 dx1
            gd x2 +- hc dx1 0
            gd y2 +- vc hd4 0
            gd iwd2 */ swd2 a 50000
            gd ihd2 */ hd2 a 50000
            gd sdx2 */ iwd2 1 2
            gd sx1 +- hc 0 iwd2
            gd sx2 +- hc 0 sdx2
            gd sx3 +- hc sdx2 0
            gd sx4 +- hc iwd2 0
            gd sdy1 sin ihd2 3600000
            gd sy1 +- vc 0 sdy1
            gd sy2 +- vc sdy1 0
            gd yAdj +- vc 0 ihd2
            ahXY gdRefY=adj minY=0 maxY=50000 x=hc y=yAdj
            cxn 0 x2 hd4
            cxn 0 x2 y2
            cxn cd4 hc b
            cxn cd2 x1 y2
            cxn cd2 x1 hd4
            cxn 3cd4 hc t
            rect sx1 sy1 sx4 sy2
            path
            M x1 hd4
            L sx2 sy1
            L hc t
            L sx3 sy1
            L x2 hd4
            L sx4 vc
            L x2 y2
            L sx3 sy2
            L hc b
            L sx2 sy2
            L x1 y2
            L sx1 vc
            Z
            """,
        "star7": """
            av adj val 34601
            av hf val 102572
            av vf val 105210
            gd a pin 0 adj 50000
            gd swd2 */ wd2 hf 100000
            gd shd2 */ hd2 vf 100000
            gd svc */ vc vf 100000
            gd dx1 */ swd2 97493 100000
            gd dx2 */ swd2 78183 100000
            gd dx3 */ swd2 43388 100000
            gd dy1 */ shd2 62349 100000
            gd dy2 */ shd2 22252 100000
            gd dy3 */ shd2 90097 100000
            gd x1 +- hc 0 dx1
            gd x2 +- hc 0 dx2
            gd x3 +- hc 0 dx3
            gd x4 +- hc dx3 0
            gd x5 +- hc dx2 0
            gd x6 +- hc dx1 0
            gd y1 +- svc 0 dy1
            gd y2 +- svc dy2 0
            gd y3 +- svc dy3 0
            gd iwd2 */ swd2 a 50000
            gd ihd2 */ shd2 a 50000
            gd sdx1 */ iwd2 97493 100000
            gd sdx2 */ iwd2 78183 100000
            gd sdx3 */ iwd2 43388 100000
            gd sx1 +- hc 0 sdx1
            gd sx2 +- hc 0 sdx2
            gd sx3 +- hc 0 sdx3
            gd sx4 +- hc sdx3 0
            gd sx5 +- hc sdx2 0
            gd sx6 +- hc sdx1 0
            gd sdy1 */ ihd2 90097 100000
            gd sdy2 */ ihd2 22252 100000
            gd sdy3 */ ihd2 62349 100000
            gd sy1 +- svc 0 sdy1
            gd sy2 +- svc 0 sdy2
            gd sy3 +- svc sdy3 0
            gd sy4 +- svc ihd2 0
            gd yAdj +- svc 0 ihd2
            ahXY gdRefY=adj minY=0 maxY=50000 x=hc y=yAdj
            cxn 0 x5 y1
            cxn 0 x6 y2
            cxn cd4 x4 y3
            cxn cd4 x3 y3
            cxn cd2 x1 y2
            cxn cd2 x2 y1
            cxn 3cd4 hc t
            rect sx2 sy1 sx5 sy3
            path
            M x1 y2
            L sx1 sy2
            L x2 y1
            L sx3 sy1
            L hc t
            L sx4 sy1
            L x5 y1
            L sx6 sy2
            L x6 y2
            L sx5 sy3
            L x4 y3
            L hc sy4
            L x3 y3
            L sx2 sy3
            Z
            """,
        "star8": """
            av adj val 37500
            gd a pin 0 adj 50000
            gd dx1 cos wd2 2700000
            gd x1 +- hc 0 dx1
            gd x2 +- hc dx1 0
            gd dy1 sin hd2 2700000
            gd y1 +- vc 0 dy1
            gd y2 +- vc dy1 0
            gd iwd2 */ wd2 a 50000
            gd ihd2 */ hd2 a 50000
            gd sdx1 */ iwd2 92388 100000
            gd sdx2 */ iwd2 38268 100000
            gd sdy1 */ ihd2 92388 100000
            gd sdy2 */ ihd2 38268 100000
            gd sx1 +- hc 0 sdx1
            gd sx2 +- hc 0 sdx2
            gd sx3 +- hc sdx2 0
            gd sx4 +- hc sdx1 0
            gd sy1 +- vc 0 sdy1
            gd sy2 +- vc 0 sdy2
            gd sy3 +- vc sdy2 0
            gd sy4 +- vc sdy1 0
            gd yAdj +- vc 0 ihd2
            ahXY gdRefY=adj minY=0 maxY=50000 x=hc y=yAdj
            cxn 0 r vc
            cxn cd4 x2 y2
            cxn cd4 hc b
            cxn cd4 x1 y2
            cxn cd2 l vc
            cxn 3cd4 x1 y1
            cxn 3cd4 hc t
            cxn 3cd4 x2 y1
            rect sx1 sy1 sx4 sy4
            path
            M l vc
            L sx1 sy2
            L x1 y1
            L sx2 sy1
            L hc t
            L sx3 sy1
            L x2 y1
            L sx4 sy2
            L r vc
            L sx4 sy3
            L x2 y2
            L sx3 sy4
            L hc b
            L sx2 sy4
            L x1 y2
            L sx1 sy3
            Z
            """,
        "verticalScroll": """
            av adj val 12500
            gd a pin 0 adj 25000
            gd ch */ ss a 100000
            gd ch2 */ ch 1 2
            gd ch4 */ ch 1 4
            gd x3 +- ch ch2 0
            gd x4 +- ch ch 0
            gd x6 +- r 0 ch
            gd x7 +- r 0 ch2
            gd x5 +- x6 0 ch2
            gd y3 +- b 0 ch
            gd y4 +- b 0 ch2
            ahXY gdRefY=adj minY=0 maxY=25000 x=l y=ch
            cxn 3cd4 hc t
            cxn 0 ch vc
            cxn cd4 hc b
            cxn cd2 x6 vc
            rect ch ch x6 y4
            path stroke=false extrusionOk=false
            M ch2 b
            A ch2 ch2 cd4 -5400000
            L ch2 y4
            A ch4 ch4 cd4 -10800000
            L ch y3
            L ch ch2
            A ch2 ch2 cd2 cd4
            L x7 t
            A ch2 ch2 3cd4 cd2
            L x6 ch
            L x6 y4
            A ch2 ch2 0 cd4
            Z
            M x4 ch2
            A ch2 ch2 0 cd4
            A ch4 ch4 cd4 cd2
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M x4 ch2
            A ch2 ch2 0 cd4
            A ch4 ch4 cd4 cd2
            Z
            M ch y4
            A ch2 ch2 0 3cd4
            A ch4 ch4 3cd4 cd2
            Z
            path fill=none extrusionOk=false
            M ch y3
            L ch ch2
            A ch2 ch2 cd2 cd4
            L x7 t
            A ch2 ch2 3cd4 cd2
            L x6 ch
            L x6 y4
            A ch2 ch2 0 cd4
            L ch2 b
            A ch2 ch2 cd4 cd2
            Z
            M x3 t
            A ch2 ch2 3cd4 cd2
            A ch4 ch4 cd4 cd2
            L x4 ch2
            M x6 ch
            L x3 ch
            M ch2 y3
            A ch4 ch4 3cd4 cd2
            L ch y4
            M ch2 b
            A ch2 ch2 cd4 -5400000
            L ch y3
            """,
        "wave": """
            av adj1 val 12500
            av adj2 val 0
            gd a1 pin 0 adj1 20000
            gd a2 pin -10000 adj2 10000
            gd y1 */ h a1 100000
            gd dy2 */ y1 10 3
            gd y2 +- y1 0 dy2
            gd y3 +- y1 dy2 0
            gd y4 +- b 0 y1
            gd y5 +- y4 0 dy2
            gd y6 +- y4 dy2 0
            gd dx1 */ w a2 100000
            gd of2 */ w a2 50000
            gd x1 abs dx1
            gd dx2 ?: of2 0 of2
            gd x2 +- l 0 dx2
            gd dx5 ?: of2 of2 0
            gd x5 +- r 0 dx5
            gd dx3 +/ dx2 x5 3
            gd x3 +- x2 dx3 0
            gd x4 +/ x3 x5 2
            gd x6 +- l dx5 0
            gd x10 +- r dx2 0
            gd x7 +- x6 dx3 0
            gd x8 +/ x7 x10 2
            gd x9 +- r 0 x1
            gd xAdj +- hc dx1 0
            gd xAdj2 +- hc 0 dx1
            gd il max x2 x6
            gd ir min x5 x10
            gd it */ h a1 50000
            gd ib +- b 0 it
            ahXY gdRefY=adj1 minY=0 maxY=20000 x=l y=y1
            ahXY gdRefX=adj2 minX=-10000 maxX=10000 x=xAdj y=b
            cxn cd4 xAdj2 y1
            cxn cd2 x1 vc
            cxn 3cd4 xAdj y4
            cxn 0 x9 vc
            rect il it ir ib
            path
            M x2 y1
            C x3 y2 x4 y3 x5 y1
            L x10 y4
            C x8 y6 x7 y5 x6 y4
            Z
            """,
    ]
}
