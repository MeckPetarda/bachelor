// =============================================================================
//  vut-fsi.typ — VUT FSI Thesis Template
//  Stage 4: cover page
// =============================================================================

// Cover page uses Vafle VUT (custom VUT corporate font).
// Font files must be placed in ./fonts/ relative to main.typ and compilation
// must include the flag:  typst compile main.typ --font-path fonts/
//
// Body uses New Computer Modern — Typst's built-in equivalent of LaTeX's
// Latin Modern Roman (the default font in diplomka.sty / lmroman12-regular).
#let _vafle     = "Vafle VUT"
#let _body-font = "New Computer Modern"

// Secondary text colour on the cover page (\Vutsub / \Vutsubs in VSKP.sty).
#let _gray = rgb("808080")

// Derives Czech/English thesis type labels from the degree code.
// Mirrors the \typstudia conditional in VSKP.sty.
#let _thesis-type(degree) = {
  if      degree == "B" { ("bakalářská práce",  "bachelor's thesis") }
  else if degree == "M" { ("diplomová práce",   "diploma thesis")    }
  else if degree == "N" { ("diplomová práce",   "master's thesis")   }
  else if degree == "D" { ("dizertační práce",  "doctoral thesis")   }
  else                  { ("neznámý typ",        "unknown type")      }
}

#let thesis(
  // Cover page metadata
  title-cs: "",
  title-en: "",
  author: "",
  author-short: "",
  supervisor: "",
  supervisor-citation: "",
  faculty-cs: "Fakulta strojního inženýrství",
  faculty-en: "Faculty of Mechanical Engineering",
  institute-cs: "",
  institute-en: "",
  degree: "B",
  year: none,

  // Front matter content
  abstract-cs: [],
  abstract-en: [],
  keywords-cs: [],
  keywords-en: [],
  declaration: [],
  acknowledgements: none,

  // Document body
  body,
) = {

  let _year = if year == none { str(datetime.today().year()) } else { str(year) }

  // ── Document metadata ────────────────────────────────────────────────────
  set document(title: title-en, author: author)

  // ── Body font ────────────────────────────────────────────────────────────
  // diplomka.sty loads lmroman12-regular (Latin Modern Roman, 12pt).
  // New Computer Modern is Typst's built-in equivalent.
  set text(font: _body-font, size: 12pt, lang: "en")

  // ── Page geometry ────────────────────────────────────────────────────────
  // Source: diplomka.sty
  //   \textwidth  16 cm
  //   \textheight 25 cm − \footskip(1 cm) = 24 cm
  //   \oddsidemargin  30 mm  (binding/inside)
  //   \evensidemargin 20 mm  (outside)  [= 210 − 160 − 30]
  //   \topmargin 15 mm + \headheight(~4 mm) + \headsep(5 mm) ≈ 24 mm to text
  //   \footskip  10 mm
  set page(
    paper: "a4",
    binding: left,
    margin: (inside: 30mm, outside: 20mm, top: 22mm, bottom: 20mm),
    numbering: "1"
  )

  set par(justify: true)

  // ── Heading numbering ────────────────────────────────────────────────────
  // diplomka.sty \@seccntformat appends a period after every counter:
  //   chapter → "1."   section → "1.1."   subsection → "1.1.1."
  // Level 4 (subsubsection) is unnumbered and excluded from the TOC.
  set heading(numbering: "1.")
  show heading.where(level: 4): set heading(numbering: "1.1.1-A")

  // ── Chapter (level 1) ────────────────────────────────────────────────────
  // diplomka.sty: \huge\bfseries\textsc + \newpage, raggedright
  //   above: 16.8pt   below: 10pt   \huge at 12pt base = 24.88pt
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    v(16.8pt, weak: true)
    block(
      width: 100%,
      align(
        left,
        text(size: 24.88pt,  smallcaps(it)),
      ),
    )
    v(10pt, weak: true)
  }

  // ── Section (level 2) ────────────────────────────────────────────────────
  // report.cls default at 12pt: \Large\bfseries = 17.28pt bold
  //   above: ~14pt   below: ~9pt
  show heading.where(level: 2): it => {
    v(14pt, weak: true)
    block(text(size: 17.28pt,  it))
    v(9pt, weak: true)
  }

  // ── Subsection (level 3) ─────────────────────────────────────────────────
  // report.cls default at 12pt: \large\bfseries = 14.4pt bold
  //   above: ~13pt   below: ~6pt
  show heading.where(level: 3): it => {
    v(13pt, weak: true)
    block(text(size: 14.4pt,  it))
    v(6pt, weak: true)
  }

  // ── Subsubsection (level 4) ──────────────────────────────────────────────
  // report.cls default at 12pt: \normalsize\bfseries = 12pt bold
  // Unnumbered, not in TOC (matches LaTeX template behaviour).
  //   above: ~12pt   below: ~6pt
  show heading.where(level: 4): it => {
    v(12pt, weak: true)
    block(text(size: 12pt,  it.body))
    v(6pt, weak: true)
  }

  // ── Cover page ───────────────────────────────────────────────────────────
  // Replicates \titul from VSKP.sty.
  // Czech is the PRIMARY language (large text); English is the subtitle (small, gray).
  // Spacing constants from VSKP.sty:
  //   Vutska 13mm · Vutskb 21mm · Vutskc 8mm
  //   Vutskd 11mm · Vutske 7mm  · Vutskf 13mm
  // Font sizes from VSKP.sty:
  //   Vutbig  25pt/30pt  · Vutmid   18pt/22pt · Vutlar   20pt/24pt (+6pt base)
  //   Vutsmall 13pt/22pt · Vutsub   11pt/13pt gray
  //                      · Vutsubs  10pt/12pt gray
  {
    set text(font: _vafle)
    set align(left)
    // All vertical rhythm comes from explicit v() calls matching VSKP.sty \vskip
    // values. Paragraph spacing is suppressed so v() values are exact.
    set par(spacing: 0pt, leading: 10pt)

    let (type-cs, type-en) = _thesis-type(degree)

    // Logo — 41 × 41 mm, keepaspectratio
    // (VSKP.sty: \includegraphics*[width=41mm,height=41mm,keepaspectratio])
    image("../logo/VUT.pdf", width: 41mm, height: 41mm, fit: "contain")

    v(19mm) // \Vutska

    // ── Institution ───────────────────────────────────────────────────────
    // English primary: Vutbig  25pt / 30pt line-height
    // Czech sub:       Vutsub  11pt / 13pt gray
    text(size: 25pt)[BRNO UNIVERSITY OF TECHNOLOGY]
    linebreak()
    text(size: 11pt, fill: _gray)[VYSOKÉ UČENÍ TECHNICKÉ V BRNĚ]

    v(8mm) // \Vutskc

    // ── Faculty ───────────────────────────────────────────────────────────
    // English primary: Vutmid  18pt / 22pt uppercase
    // Czech sub:       Vutsub  11pt / 13pt gray
    text(size: 16pt)[#upper(faculty-en)]
    linebreak()
    text(size: 11pt, fill: _gray)[#upper(faculty-cs)]

    v(8mm) // \Vutskc

    // ── Institute ─────────────────────────────────────────────────────────
    text(size: 16pt)[#upper(institute-en)]
    linebreak()
    text(size: 11pt, fill: _gray)[#upper(institute-cs)]

    v(27mm) // \Vutskb

    // ── Thesis title ──────────────────────────────────────────────────────
    // VSKP.sty: \advance\baselineskip by 6pt → at 20pt base = 30pt line-height
    //           → leading (extra gap between wrapped lines) = 30 − 20 = 10pt
    // `leading` is a par() property, not text(), so scope it with a block.
    // English primary: Vutlar  20pt, leading 10pt
    // Czech sub:       Vutsub  11pt gray
    text(size: 18pt)[#upper(title-en)]
    linebreak()
    text(size: 11pt, fill: _gray)[#upper(title-cs)]

    v(20mm) // \Vutskd

    // ── Thesis type ───────────────────────────────────────────────────────
    // English primary: Vutsmall 13pt
    // Czech sub:       Vutsubs  10pt gray
    text(size: 14pt)[#upper(type-en)]
    linebreak()
    text(size: 11pt, fill: _gray)[#upper(type-cs)]

    v(7mm) // \Vutske

    // ── Author ────────────────────────────────────────────────────────────
    // VSKP.sty: \hbox to 5cm{AUTOR PRÁCE\hss}\hskip2cm\Autortxt
    // English label primary (13pt), Czech label subtitle (10pt gray)
    grid(
      columns: (5cm, 2cm, auto),
      gutter: 0pt,
      text(size: 14pt)[AUTHOR], [], text(size: 14pt)[#author],
    )
    v(8pt)
    text(size: 11pt, fill: _gray)[AUTOR PRÁCE]

    v(7mm) // \Vutske

    // ── Supervisor ────────────────────────────────────────────────────────
    grid(
      columns: (5cm, 2cm, auto),
      gutter: 0pt,
      text(size: 14pt)[SUPERVISOR], [], text(size: 14pt)[#supervisor],
    )
    v(8pt)
    text(size: 11pt, fill: _gray)[VEDOUCÍ PRÁCE]

    v(25mm) // \Vutskf

    // ── City / year ───────────────────────────────────────────────────────
    text(size: 13pt)[BRNO #_year]
  }

  pagebreak()

  // ── Abstract page ────────────────────────────────────────────────────────
  [
    *Abstract page placeholder*

    *Abstrakt*

    #abstract-cs

    *Summary*

    #abstract-en

    *Klíčová slova*

    #keywords-cs

    *Keywords*

    #keywords-en
  ]

  pagebreak()

  // ── Declaration ──────────────────────────────────────────────────────────
  [
    *Declaration placeholder*

    #declaration
  ]

  pagebreak()

  // ── Acknowledgements (optional) ──────────────────────────────────────────
  if acknowledgements != none [
    *Acknowledgements placeholder*

    #acknowledgements

    #pagebreak()
  ]

  // ── Table of contents ────────────────────────────────────────────────────
  outline(depth: 3, indent: auto)

  pagebreak()

  // ── Body ─────────────────────────────────────────────────────────────────
  body
}
