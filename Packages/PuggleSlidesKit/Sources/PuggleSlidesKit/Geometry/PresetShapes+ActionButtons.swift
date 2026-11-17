// DrawingML preset shapes, transcribed from ECMA-376 Part 1's presetShapeDefinitions.xml. See PresetShapeDefinition
// for the statement syntax and the errata fixed.

extension PresetShapeSource {
    static let actionButtons: [String: String] = [
        "actionButtonBackPrevious": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g10 +- vc dx2 0
            gd g11 +- hc 0 dx2
            gd g12 +- hc dx2 0
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M g11 vc
            L g12 g9
            L g12 g10
            Z
            path fill=darken stroke=false extrusionOk=false
            M g11 vc
            L g12 g9
            L g12 g10
            Z
            path fill=none extrusionOk=false
            M g11 vc
            L g12 g9
            L g12 g10
            Z
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonBeginning": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g10 +- vc dx2 0
            gd g11 +- hc 0 dx2
            gd g12 +- hc dx2 0
            gd g13 */ ss 3 4
            gd g14 */ g13 1 8
            gd g15 */ g13 1 4
            gd g16 +- g11 g14 0
            gd g17 +- g11 g15 0
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M g17 vc
            L g12 g9
            L g12 g10
            Z
            M g16 g9
            L g11 g9
            L g11 g10
            L g16 g10
            Z
            path fill=darken stroke=false extrusionOk=false
            M g17 vc
            L g12 g9
            L g12 g10
            Z
            M g16 g9
            L g11 g9
            L g11 g10
            L g16 g10
            Z
            path fill=none extrusionOk=false
            M g17 vc
            L g12 g9
            L g12 g10
            Z
            M g16 g9
            L g16 g10
            L g11 g10
            L g11 g9
            Z
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonBlank": """
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonDocument": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g10 +- vc dx2 0
            gd dx1 */ ss 9 32
            gd g11 +- hc 0 dx1
            gd g12 +- hc dx1 0
            gd g13 */ ss 3 16
            gd g14 +- g12 0 g13
            gd g15 +- g9 g13 0
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M g11 g9
            L g14 g9
            L g12 g15
            L g12 g10
            L g11 g10
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M g11 g9
            L g14 g9
            L g14 g15
            L g12 g15
            L g12 g10
            L g11 g10
            Z
            path fill=darken stroke=false extrusionOk=false
            M g14 g9
            L g14 g15
            L g12 g15
            Z
            path fill=none extrusionOk=false
            M g11 g9
            L g14 g9
            L g12 g15
            L g12 g10
            L g11 g10
            Z
            M g12 g15
            L g14 g15
            L g14 g9
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonEnd": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g10 +- vc dx2 0
            gd g11 +- hc 0 dx2
            gd g12 +- hc dx2 0
            gd g13 */ ss 3 4
            gd g14 */ g13 3 4
            gd g15 */ g13 7 8
            gd g16 +- g11 g14 0
            gd g17 +- g11 g15 0
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M g16 vc
            L g11 g9
            L g11 g10
            Z
            M g17 g9
            L g12 g9
            L g12 g10
            L g17 g10
            Z
            path fill=darken stroke=false extrusionOk=false
            M g16 vc
            L g11 g9
            L g11 g10
            Z
            M g17 g9
            L g12 g9
            L g12 g10
            L g17 g10
            Z
            path fill=none extrusionOk=false
            M g16 vc
            L g11 g10
            L g11 g9
            Z
            M g17 g9
            L g12 g9
            L g12 g10
            L g17 g10
            Z
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonForwardNext": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g10 +- vc dx2 0
            gd g11 +- hc 0 dx2
            gd g12 +- hc dx2 0
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M g12 vc
            L g11 g9
            L g11 g10
            Z
            path fill=darken stroke=false extrusionOk=false
            M g12 vc
            L g11 g9
            L g11 g10
            Z
            path fill=none extrusionOk=false
            M g12 vc
            L g11 g10
            L g11 g9
            Z
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonHelp": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g11 +- hc 0 dx2
            gd g13 */ ss 3 4
            gd g14 */ g13 1 7
            gd g15 */ g13 3 14
            gd g16 */ g13 2 7
            gd g19 */ g13 3 7
            gd g20 */ g13 4 7
            gd g21 */ g13 17 28
            gd g23 */ g13 21 28
            gd g24 */ g13 11 14
            gd g27 +- g9 g16 0
            gd g29 +- g9 g21 0
            gd g30 +- g9 g23 0
            gd g31 +- g9 g24 0
            gd g33 +- g11 g15 0
            gd g36 +- g11 g19 0
            gd g37 +- g11 g20 0
            gd g41 */ g13 1 14
            gd g42 */ g13 3 28
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M g33 g27
            A g16 g16 cd2 cd2
            A g14 g15 0 cd4
            A g41 g42 3cd4 -5400000
            L g37 g30
            L g36 g30
            L g36 g29
            A g14 g15 cd2 cd4
            A g41 g42 cd4 -5400000
            A g14 g14 0 -10800000
            Z
            M hc g31
            A g42 g42 3cd4 21600000
            Z
            path fill=darken stroke=false extrusionOk=false
            M g33 g27
            A g16 g16 cd2 cd2
            A g14 g15 0 cd4
            A g41 g42 3cd4 -5400000
            L g37 g30
            L g36 g30
            L g36 g29
            A g14 g15 cd2 cd4
            A g41 g42 cd4 -5400000
            A g14 g14 0 -10800000
            Z
            M hc g31
            A g42 g42 3cd4 21600000
            Z
            path fill=none extrusionOk=false
            M g33 g27
            A g16 g16 cd2 cd2
            A g14 g15 0 cd4
            A g41 g42 3cd4 -5400000
            L g37 g30
            L g36 g30
            L g36 g29
            A g14 g15 cd2 cd4
            A g41 g42 cd4 -5400000
            A g14 g14 0 -10800000
            Z
            M hc g31
            A g42 g42 3cd4 21600000
            Z
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonHome": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g10 +- vc dx2 0
            gd g11 +- hc 0 dx2
            gd g12 +- hc dx2 0
            gd g13 */ ss 3 4
            gd g14 */ g13 1 16
            gd g15 */ g13 1 8
            gd g16 */ g13 3 16
            gd g17 */ g13 5 16
            gd g18 */ g13 7 16
            gd g19 */ g13 9 16
            gd g20 */ g13 11 16
            gd g21 */ g13 3 4
            gd g22 */ g13 13 16
            gd g23 */ g13 7 8
            gd g24 +- g9 g14 0
            gd g25 +- g9 g16 0
            gd g26 +- g9 g17 0
            gd g27 +- g9 g21 0
            gd g28 +- g11 g15 0
            gd g29 +- g11 g18 0
            gd g30 +- g11 g19 0
            gd g31 +- g11 g20 0
            gd g32 +- g11 g22 0
            gd g33 +- g11 g23 0
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M hc g9
            L g11 vc
            L g28 vc
            L g28 g10
            L g33 g10
            L g33 vc
            L g12 vc
            L g32 g26
            L g32 g24
            L g31 g24
            L g31 g25
            Z
            path fill=darkenLess stroke=false extrusionOk=false
            M g32 g26
            L g32 g24
            L g31 g24
            L g31 g25
            Z
            M g28 vc
            L g28 g10
            L g29 g10
            L g29 g27
            L g30 g27
            L g30 g10
            L g33 g10
            L g33 vc
            Z
            path fill=darken stroke=false extrusionOk=false
            M hc g9
            L g11 vc
            L g12 vc
            Z
            M g29 g27
            L g30 g27
            L g30 g10
            L g29 g10
            Z
            path fill=none extrusionOk=false
            M hc g9
            L g31 g25
            L g31 g24
            L g32 g24
            L g32 g26
            L g12 vc
            L g33 vc
            L g33 g10
            L g28 g10
            L g28 vc
            L g11 vc
            Z
            M g31 g25
            L g32 g26
            M g33 vc
            L g28 vc
            M g29 g10
            L g29 g27
            L g30 g27
            L g30 g10
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonInformation": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g11 +- hc 0 dx2
            gd g13 */ ss 3 4
            gd g14 */ g13 1 32
            gd g17 */ g13 5 16
            gd g18 */ g13 3 8
            gd g19 */ g13 13 32
            gd g20 */ g13 19 32
            gd g22 */ g13 11 16
            gd g23 */ g13 13 16
            gd g24 */ g13 7 8
            gd g25 +- g9 g14 0
            gd g28 +- g9 g17 0
            gd g29 +- g9 g18 0
            gd g30 +- g9 g23 0
            gd g31 +- g9 g24 0
            gd g32 +- g11 g17 0
            gd g34 +- g11 g19 0
            gd g35 +- g11 g20 0
            gd g37 +- g11 g22 0
            gd g38 */ g13 3 32
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M hc g9
            A dx2 dx2 3cd4 21600000
            Z
            path fill=darken stroke=false extrusionOk=false
            M hc g9
            A dx2 dx2 3cd4 21600000
            Z
            M hc g25
            A g38 g38 3cd4 21600000
            M g32 g28
            L g32 g29
            L g34 g29
            L g34 g30
            L g32 g30
            L g32 g31
            L g37 g31
            L g37 g30
            L g35 g30
            L g35 g28
            Z
            path fill=lighten stroke=false extrusionOk=false
            M hc g25
            A g38 g38 3cd4 21600000
            M g32 g28
            L g35 g28
            L g35 g30
            L g37 g30
            L g37 g31
            L g32 g31
            L g32 g30
            L g34 g30
            L g34 g29
            L g32 g29
            Z
            path fill=none extrusionOk=false
            M hc g9
            A dx2 dx2 3cd4 21600000
            Z
            M hc g25
            A g38 g38 3cd4 21600000
            M g32 g28
            L g35 g28
            L g35 g30
            L g37 g30
            L g37 g31
            L g32 g31
            L g32 g30
            L g34 g30
            L g34 g29
            L g32 g29
            Z
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonMovie": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g10 +- vc dx2 0
            gd g11 +- hc 0 dx2
            gd g12 +- hc dx2 0
            gd g13 */ ss 3 4
            gd g14 */ g13 1455 21600
            gd g15 */ g13 1905 21600
            gd g16 */ g13 2325 21600
            gd g17 */ g13 16155 21600
            gd g18 */ g13 17010 21600
            gd g19 */ g13 19335 21600
            gd g20 */ g13 19725 21600
            gd g21 */ g13 20595 21600
            gd g22 */ g13 5280 21600
            gd g23 */ g13 5730 21600
            gd g24 */ g13 6630 21600
            gd g25 */ g13 7492 21600
            gd g26 */ g13 9067 21600
            gd g27 */ g13 9555 21600
            gd g28 */ g13 13342 21600
            gd g29 */ g13 14580 21600
            gd g30 */ g13 15592 21600
            gd g31 +- g11 g14 0
            gd g32 +- g11 g15 0
            gd g33 +- g11 g16 0
            gd g34 +- g11 g17 0
            gd g35 +- g11 g18 0
            gd g36 +- g11 g19 0
            gd g37 +- g11 g20 0
            gd g38 +- g11 g21 0
            gd g39 +- g9 g22 0
            gd g40 +- g9 g23 0
            gd g41 +- g9 g24 0
            gd g42 +- g9 g25 0
            gd g43 +- g9 g26 0
            gd g44 +- g9 g27 0
            gd g45 +- g9 g28 0
            gd g46 +- g9 g29 0
            gd g47 +- g9 g30 0
            gd g48 +- g9 g31 0
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M g11 g39
            L g11 g44
            L g31 g44
            L g32 g43
            L g33 g43
            L g33 g47
            L g35 g47
            L g35 g45
            L g36 g45
            L g38 g46
            L g12 g46
            L g12 g41
            L g38 g41
            L g37 g42
            L g35 g42
            L g35 g41
            L g34 g40
            L g32 g40
            L g31 g39
            Z
            path fill=darken stroke=false extrusionOk=false
            M g11 g39
            L g11 g44
            L g31 g44
            L g32 g43
            L g33 g43
            L g33 g47
            L g35 g47
            L g35 g45
            L g36 g45
            L g38 g46
            L g12 g46
            L g12 g41
            L g38 g41
            L g37 g42
            L g35 g42
            L g35 g41
            L g34 g40
            L g32 g40
            L g31 g39
            Z
            path fill=none extrusionOk=false
            M g11 g39
            L g31 g39
            L g32 g40
            L g34 g40
            L g35 g41
            L g35 g42
            L g37 g42
            L g38 g41
            L g12 g41
            L g12 g46
            L g38 g46
            L g36 g45
            L g35 g45
            L g35 g47
            L g33 g47
            L g33 g43
            L g32 g43
            L g31 g44
            L g11 g44
            Z
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonReturn": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g10 +- vc dx2 0
            gd g11 +- hc 0 dx2
            gd g12 +- hc dx2 0
            gd g13 */ ss 3 4
            gd g14 */ g13 7 8
            gd g15 */ g13 3 4
            gd g16 */ g13 5 8
            gd g17 */ g13 3 8
            gd g18 */ g13 1 4
            gd g19 +- g9 g15 0
            gd g20 +- g9 g16 0
            gd g21 +- g9 g18 0
            gd g22 +- g11 g14 0
            gd g23 +- g11 g15 0
            gd g24 +- g11 g16 0
            gd g25 +- g11 g17 0
            gd g26 +- g11 g18 0
            gd g27 */ g13 1 8
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M g12 g21
            L g23 g9
            L hc g21
            L g24 g21
            L g24 g20
            A g27 g27 0 cd4
            L g25 g19
            A g27 g27 cd4 cd4
            L g26 g21
            L g11 g21
            L g11 g20
            A g17 g17 cd2 -5400000
            L hc g10
            A g17 g17 cd4 -5400000
            L g22 g21
            Z
            path fill=darken stroke=false extrusionOk=false
            M g12 g21
            L g23 g9
            L hc g21
            L g24 g21
            L g24 g20
            A g27 g27 0 cd4
            L g25 g19
            A g27 g27 cd4 cd4
            L g26 g21
            L g11 g21
            L g11 g20
            A g17 g17 cd2 -5400000
            L hc g10
            A g17 g17 cd4 -5400000
            L g22 g21
            Z
            path fill=none extrusionOk=false
            M g12 g21
            L g22 g21
            L g22 g20
            A g17 g17 0 cd4
            L g25 g10
            A g17 g17 cd4 cd4
            L g11 g21
            L g26 g21
            L g26 g20
            A g27 g27 cd2 -5400000
            L hc g19
            A g27 g27 cd4 -5400000
            L g24 g21
            L hc g21
            L g23 g9
            Z
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
        "actionButtonSound": """
            gd dx2 */ ss 3 8
            gd g9 +- vc 0 dx2
            gd g10 +- vc dx2 0
            gd g11 +- hc 0 dx2
            gd g12 +- hc dx2 0
            gd g13 */ ss 3 4
            gd g14 */ g13 1 8
            gd g15 */ g13 5 16
            gd g16 */ g13 5 8
            gd g17 */ g13 11 16
            gd g18 */ g13 3 4
            gd g19 */ g13 7 8
            gd g20 +- g9 g14 0
            gd g21 +- g9 g15 0
            gd g22 +- g9 g17 0
            gd g23 +- g9 g19 0
            gd g24 +- g11 g15 0
            gd g25 +- g11 g16 0
            gd g26 +- g11 g18 0
            cxn 0 r vc
            cxn cd4 hc b
            cxn cd2 l vc
            cxn 3cd4 hc t
            rect l t r b
            path stroke=false extrusionOk=false
            M l t
            L r t
            L r b
            L l b
            Z
            M g11 g21
            L g11 g22
            L g24 g22
            L g25 g10
            L g25 g9
            L g24 g21
            Z
            path fill=darken stroke=false extrusionOk=false
            M g11 g21
            L g11 g22
            L g24 g22
            L g25 g10
            L g25 g9
            L g24 g21
            Z
            path fill=none extrusionOk=false
            M g11 g21
            L g24 g21
            L g25 g9
            L g25 g10
            L g24 g22
            L g11 g22
            Z
            M g26 g21
            L g12 g20
            M g26 vc
            L g12 vc
            M g26 g22
            L g12 g23
            path fill=none
            M l t
            L r t
            L r b
            L l b
            Z
            """,
    ]
}
