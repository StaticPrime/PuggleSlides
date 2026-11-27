# PuggleSlides

**Present with confidence.**

PuggleSlides is a presentation app for the Mac. Build a deck in minutes with ready-made themes, then present it full screen with your notes, the next slide and a timer in front of you.

- Eight themes, eleven layouts and 134 shapes
- Tables, charts, word art, videos, sounds and image tools
- Transitions and animations that play just as you planned them
- Presenter view with speaker notes, the next slide and a timer
- Comments, find and replace, grid view, handouts and printing
- Collaborate live with other Mac users through iCloud, each person able to edit or only comment

It opens and saves PowerPoint (.pptx) and OpenDocument (.odp) files, and exports PDF, PNG, JPEG, SVG and plain text.

PuggleSlides is free, needs no account and has no tracking. It runs inside Apple's app sandbox, and the only connection it makes itself is to GitHub as it opens, to see whether there's a new version (macOS takes the presentations you share to and from iCloud for it). It runs on macOS 14 Sonoma or later with Apple silicon or Intel. It's written in Swift with AppKit and SwiftUI, and is part of the PuggleSoft family with [PuggleDocs](https://github.com/StaticPrime/PuggleDocs) and [PuggleSheets](https://github.com/StaticPrime/PuggleSheets).

## Features

### Editing

- **The window.** A familiar layout: the filmstrip of slide thumbnails on the left, the slide in the middle on a gray canvas, speaker notes underneath (drag the divider, or View ▸ Show speaker notes), and panels on the right. The header has the title (click to rename), the format badge, the save status, version history, the Slideshow button with its menu, and Download. The toolbar changes with what's selected: Background, Layout and Theme with nothing selected; fill and border color, border weight and dash for shapes; font, size, bold, italic, underline, text and highlight color, link, alignment, line and paragraph spacing, bulleted and numbered lists, indents and clear formatting for text; line color, weight, dash, start and end for lines. Groups that don't fit move into a "More" menu.
- **Slides.** New slide (⌃M) picks the next layout (after a title slide, "Title and body"; otherwise the current slide's), or any layout from the + menu. Duplicate, delete, skip and move slides from the Slide menu, the filmstrip's context menu or its keys (⌘↑ and ⌘↓ move, ⇧⌘↑ and ⇧⌘↓ move to the beginning or end); drag thumbnails to reorder them; Shift-click and ⌘-click select several. Skipped slides are dimmed with a crossed-out eye. Slide ▸ Apply layout moves text into the new layout's placeholders, and Insert ▸ Slide numbers numbers every slide (or all but title slides).
- **Themes and layouts.** Eight themes with eleven layouts (Title slide, Section header, Title and body, Title and two columns, Title only, One column text, Main point, Section title and description, Caption, Big number, Blank): Simple Light, the default, plus Simple Dark, Puggle, Harbor, Meadow, Midnight, Paperback and Citrus. Placeholders inherit their position, font, size, color, bullets and text fitting from their layout and theme, so changing the theme restyles every slide while keeping anything formatted by hand. Slide ▸ Change background sets a color or an image for the selected slides, resets to the theme or adds the background to the theme.
- **Theme builder.** Slide ▸ Edit theme (or View ▸ Theme builder) shows the theme and its layouts in the filmstrip, to edit like slides: move and format placeholders, add shapes, pictures and text, change backgrounds, add placeholders (Insert ▸ Placeholder), rename the theme or a layout, and duplicate layouts or delete ones no slide uses. Colors changes the theme's twelve colors, and everything that uses them follows. All of it is one undo step once the builder closes; in a shared presentation, everyone sees each change as it's made.
- **Text.** Click a text box or placeholder to type in it (empty placeholders show "Click to add title" and the other prompts); double-click or start typing to edit a shape's text. Rich text with fonts, sizes, bold, italic, underline, strikethrough, superscript and subscript, text and highlight colors (including the theme's colors), links to web pages or other slides, alignment, line spacing and space before and after paragraphs, bulleted and numbered lists with nine levels (Tab and Shift-Tab change the level, Return on an empty item ends the list), and text fitting: "Resize shape to fit text" (the default for text boxes), "Shrink text on overflow" (the default for placeholders) and "Do not autofit", with indentation padding.
- **Typing.** PuggleSlides ▸ Settings… (⌘,) sets how typing behaves in text boxes, placeholders, tables and speaker notes: smart quotes and smart dashes (on unless you turn them off), a capital for the first word of each sentence and line (off unless you turn it on), and checking spelling as you type (also Tools ▸ Spell check). The capital comes as you type the space after the word; Undo takes back just the capital, and words such as iPhone, web addresses and words after abbreviations such as "e.g." are left as typed. A change reaches text you're typing straight away. macOS's own Capitalize words automatically doesn't apply in presentations, so the setting here decides.
- **Shapes, lines and images.** Insert ▸ Shape and the toolbar's Shape button have the shape gallery: 134 shapes, arrows, callouts (with the stars and banners) and equation shapes (with the brackets and braces). Every shape is drawn from the Office Open XML definitions, so it looks as it does in PowerPoint at any size, and yellow handles adjust corners, arrow heads and points. Lines, arrows, elbow and curved connectors take line ends (fill and stroke arrows, circles, squares and diamonds). Images come from Insert ▸ Image, the clipboard or a drop onto the slide, with crops and masks from files kept. Shapes get a default look: the theme's first accent color with a thin dark border.
- **Image tools.** Crop image (or a double-click on a picture) shows black crop marks: Return keeps the crop and Esc puts it back. Mask image cuts a picture to any shape in the gallery, Replace image puts another picture in the same place and mask, and Reset image takes back the crop, mask and adjustments. Format options adds Recolor (light and dark versions of the theme's ten colors, grayscale, negative and sepia) and Adjustments (opacity, brightness and contrast).
- **Video and audio.** Insert ▸ Video and Insert ▸ Audio embed a movie or a sound from your Mac, or drop one on the slide: a video shows its first frame until it plays, and a sound shows as a speaker icon. Double-click a clip, or click a selected video's play button, to play it on the slide. Format options sets when a video plays (on click, automatically or manually), where it starts and ends, and whether it's muted; and for a sound, when it starts, its volume, whether it loops, whether its icon hides while presenting and whether it stops when the slide changes.
- **Tables.** Insert ▸ Table picks the size on a grid, up to 20 × 20. Click a cell to type in it; Tab and Shift-Tab move between cells, Tab in the last cell adds a row, and rows grow to fit their text. Drag across cells (or Shift-click) to select them, then fill them, set their borders (all, inner, outer, horizontal, vertical or one side, each with its color, weight and dash), align or format their text, or press Delete to clear them. Insert and delete rows and columns, merge and unmerge cells, and distribute rows and columns from Format ▸ Table or the right-click menu; drag the lines between columns and rows to resize them.
- **Charts.** Insert ▸ Chart adds a bar, column, line or pie chart of sample numbers. PuggleSlides keeps a chart's numbers with the chart, and the chart editor (Edit chart, or double-click the chart) changes the numbers and labels, the type (column, bar, line, area, pie, doughnut or scatter, with stacked and 100% stacked versions), the titles, legend, gridlines, data labels, axis range and series colors. Charts are drawn by the same chart engine as PuggleSheets.
- **Word art.** Insert ▸ Word art: the letters fill their box as it's resized, painted with the toolbar's fill and border color, weight and dash. Double-click word art to change its text.
- **Arranging.** Drag to move (Shift keeps the direction, Option drags a copy), resize from any handle (Shift keeps the proportions, Option resizes from the center; dragging past the other side flips), turn with the rotation handle (Shift snaps to 15°), nudge with the arrow keys and rotate with ⌥← and ⌥→. Arrange ▸ Order, Align, Distribute, Center on page, Rotate and flip, Group and Ungroup. Format options sets the exact size, rotation and position in inches.
- **Lining things up.** Objects snap to the slide's edges and middle, to other objects and to guides as they move or resize, with red lines showing what they line up with (View ▸ Snap to ▸ Guides, on by default; Snap to ▸ Grid uses an eighth of an inch; hold Command to move freely). View ▸ Guides adds vertical and horizontal guides that show on every slide: drag them, edit their positions and colors, delete one by dragging it off the slide or right-clicking it, or clear them all. View ▸ Show ruler (⇧⌘R) adds inch rulers along the canvas.
- **Undo, copy and paste.** Undo and redo for everything (typing in a text box is one step when you finish); cut, copy and paste shapes and slides between presentations, with pasted slides taking the destination's theme; Paste without formatting; ⌘D duplicates; Paint format copies a shape's look to the next shape you click.
- **Find and replace.** Edit ▸ Find and replace (⇧⌘H) or Find (⌘F) opens a dialog: Find, Replace with, Match case and Match using regular expressions, with Prev, Next, Replace and Replace all. It searches text boxes, shapes, groups, table cells and speaker notes. Matches on the slide are marked in yellow and the current one in orange, and the dialog counts them ("3 of 12"). Find again (⌘G) and Find previous (⇧⌘G) step through them; replacements keep the formatting of the text they replace, and Replace all is one undo step.
- **Importing.** File ▸ Import slides picks slides from another PowerPoint or OpenDocument presentation, keeping their own theme or taking this one's (and slides from a page of another size are scaled to fit). The Themes panel's Import theme uses another presentation's theme.
- **Grid view.** View ▸ Grid view (⌥⌘1) shows every slide in rows, with a zoom slider. Select, drag to reorder, and double-click or press Return to open a slide.

### Comments and accessibility

- **Comments.** Insert ▸ Comment (⌥⌘M), or Comment in the right-click menu, starts a discussion about the selected object or the slide. Comments show as cards to the right of the slide: reply, edit or delete from More, and resolve with the check mark; selecting an object selects its comment. The header's comments button (⌥⇧⌘A) opens the comments panel, which lists every comment by slide, shows all, open or resolved ones, searches them, and re-opens resolved ones. View ▸ Comments ▸ Show comments (⌥⇧⌘J) hides the cards. Comments are signed with the Mac account's name, stay behind when a slide is duplicated, copied or imported, and each change is one undo step.
- **Accessibility.** VoiceOver reads the slide as a group of its objects, each by its alt text, its text or what it is (image, chart, table, shape, line), placed where it's drawn, and the filmstrip as a list of slides with their titles, skipped slides and comments; a slideshow announces each slide's text as it arrives. Tab and Shift-Tab move between objects and Return edits one, and keyboard shortcuts move to the filmstrip (⌥⇧⌘F), the slide (⌥⇧⌘C) and the speaker notes (⌥⇧⌘S). Every toolbar button has a name VoiceOver reads.

### Collaboration

- **Collaborate.** The Collaborate button in the header, left of Download (or File ▸ Collaborate…, ⌥⌘C), which only a presentation's owner has, shares a presentation with other people who use PuggleSlides on their Macs, through iCloud. A presentation is kept on your Mac first: one that has never been saved asks where, and that file stays yours. Invite Collaborators sends the link by Messages, Mail or AirDrop, where you choose whether the people you invite can make changes; or choose Anyone with the Link, whether those people can edit or only comment, and Copy Link to pass it on yourself. Whoever clicks the link joins, and the presentation opens for them in PuggleSlides. If clicking it opens a web page instead, copy the link and choose File ▸ Shared presentations ▸ Open Invitation Link….
- **Live.** Everyone's changes show on everyone else's Mac as they're made: slides added, moved and deleted, objects moved, resized and restyled, text as it's typed, speaker notes, backgrounds, layouts, transitions and animations, and themes edited in the theme builder. Changes to different slides and objects all stand, and so do changes to different sides of one object: one person can move a text box while another types in it. Undo takes back only your own changes, as one step per edit.
- **Who's here.** Everyone who has opened it shows as a round badge with their initials in the header, with a green dot while they have it open. Each person's Mac says who they are when they open it, so names show even when iCloud doesn't give them. Click a badge to see their name, their email address or phone number when iCloud says it, whether they own it, edit or comment, and when they were last there.
- **Edit or comment.** In the Collaborate sheet the owner sets, person by person, whether each can edit or only comment, and can take anyone out. People who can only comment see every change as it's made and add comments and replies, but can't change the slides: the toolbar says Commenting, and iCloud itself turns their changes down. Everyone can present a shared presentation, print it and save a copy of it on their Mac (File ▸ Save, Make a copy, or Download), whatever they can do. In a shared presentation, people edit and delete the comments they wrote; those who can edit can delete any.
- **Notifications.** When someone changes a shared presentation and then does nothing more to it for two minutes, everyone else gets one notification summing it up ("Ana Lopez edited “Launch plan”: added 2 slides, edited 3 slides and added a comment"), not one for every change, even when PuggleSlides isn't open. Clicking it opens the presentation.
- **Offline.** When iCloud can't be reached (the Mac is offline, say), a shared presentation turns read-only and the window says why: you can still see it, comments included, present it, print it and save a copy, but not change it or comment on it, and Undo waits too. Nothing is kept to send later. As soon as iCloud can be reached again it catches up with what everyone else did meanwhile and can be changed again. A shared presentation opened while offline opens once iCloud can be reached.
- **Stopping.** Stop Sharing… in the Collaborate sheet takes the presentation out of your iCloud and from everyone it was shared with, and keeps it on your Mac, saved as it was. Anyone who has it open sees it go at once, with a note saying you stopped sharing it. People can also leave a presentation shared with them, with File ▸ Leave shared presentation…. File ▸ Shared presentations lists the presentations shared with you and those you share.

### Presenting

- **Slideshow.** View ▸ Slideshow (⌘↩) or the Slideshow button presents full screen from the current slide (⇧⌘↩ from the beginning), leaving out skipped slides. The usual keys work: the arrows, Space, Page Up and Page Down, Home and End, a slide number then Return, B or . for a black screen, W or , for a white one, and Esc. Moving the mouse shows the control bar. Transitions and animations play in order: whatever comes before the first "On click" plays when the slide appears, each click starts the next group, and a click while something is moving finishes it. Going back a click takes the last group back; going back a slide shows it fully built. Videos and sounds play when their slide appears, on the next click once the slide's animations have played, or when the video itself is clicked, as Format options says; a sound can play on over the slides after its own.
- **Motion.** The Motion panel (View ▸ Motion, ⌥⇧⌘B, or the toolbar's Transition and Animate buttons) sets the selected slides' transition (Dissolve, Fade, Slide from right, Slide from left, Flip, Cube or Gallery) with its speed, or applies it to all slides. Insert ▸ Animation animates the selected object: Appear, Fade in, Fly in from the left, right, bottom or top, Zoom in and Spin, and the matching exits. Each animation starts On click, After previous or With previous, has its own speed, and can play text By paragraph; drag the cards to reorder them, and Play previews the slide in place. Slides with motion are marked in the filmstrip.
- **Presenter view.** Slideshow ▸ Presenter view shows the current and next slides, the speaker notes (with a text size control), a timer you can pause and reset, and Previous and Next. With a second display the audience sees the slides there; with one, presenter view floats over the show. Closing it ends the show.

### Files and output

- **PowerPoint files.** Open and save **Microsoft PowerPoint (.pptx)** with our own reader and writer: themes, layouts and placeholders with their inheritance, shapes and freeforms, lines and connectors, pictures with their crops, adjustments and recolors, groups, rich text and lists, links, slide numbers, backgrounds, skipped slides, speaker notes, transitions and animations, tables with their merges, fills, borders and margins (and PowerPoint's table styles when reading), charts as PowerPoint charts whose numbers can be edited there, word art, guides with their colors, videos and sounds embedded as PowerPoint embeds them, with their posters, start and end times, volume, mute, looping, hidden icons and when they play, and comments as PowerPoint 365 keeps them, with their replies, whether they're resolved and the objects they're about (older PowerPoint comments open too).
- **OpenDocument files.** OpenDocument presentations (.odp), the format of LibreOffice Impress, open and save too: themes and layouts (as LibreOffice's masters and page layouts), placeholders, shapes, lines and their ends, pictures with crops, groups, rich text and lists, slide numbers, backgrounds, speaker notes, skipped slides, transitions and animations, tables with their cell styles (and LibreOffice's table designs when reading), charts as embedded chart objects with their own numbers, word art as Fontwork, picture opacity, brightness, contrast and grayscale, guides as snap lines, videos and sounds as LibreOffice Impress media, with their loop, mute, volume and when they play, and comments as LibreOffice keeps them, with replies and resolved threads marked as LibreOffice Writer marks them. Files in either format with things PuggleSlides can't keep (SmartArt, video and so on) open as an untitled copy with a notice, so the original is never overwritten with less.
- **Printing.** File ▸ Print settings and preview has these layouts: one slide per page with or without notes, or handouts of 1, 2, 3, 4, 6 or 9 slides per page in portrait or landscape, with Hide background and Include skipped slides. Print (⌘P) from there or straight away, or Download as PDF.
- **Downloads.** File ▸ Download offers Microsoft PowerPoint (.pptx), ODP Document (.odp), PDF Document (.pdf), Plain Text (.txt), and the current slide as a JPEG or PNG image (1600 pixels wide) or as Scalable Vector Graphics (.svg) with real text and shapes.
- **macOS integration.** Autosave, version history, Make a copy, Rename, Move, Page setup (16:9, 16:10, 4:3 or custom), and the menus in the macOS menu bar.

### Updates

- **Splash screen.** As it opens, PuggleSlides shows its logo while it asks GitHub whether there's a new version. If GitHub hasn't answered within 5 seconds, PuggleSlides opens without waiting for it.
- **Automatic Updates.** PuggleSlides ▸ Settings… (⌘,), on unless you turn it off. When PuggleSlides opens and there's a new version, the splash screen says "PuggleSlides is Updating" with a bar showing the download as it arrives, then an "Updating…" bar showing macOS's installer putting it in place, and the new version opens, with any presentations that were waiting to open. macOS asks for an administrator's password to install it, as PuggleSlides is installed for everyone on the Mac. Cancelling the download or the password dialog opens PuggleSlides as it is, and that version isn't installed by itself again; the banner offers it instead.
- **Update banner.** With Automatic Updates off, a banner under the toolbar of each presentation's window says when a new version is available (slideshows and presenter view never show it). **Click Here** downloads and installs it the same way, then closes the open presentations (saving them) and opens them again in the new version. **Dismiss** hides the banner until PuggleSlides next opens.
- **Checked before it's installed.** An update is installed only if it's the file the release describes (its size and SHA-256), signed by the same developer as the copy that's running, and notarized by Apple.
- **App Store.** A copy from the App Store is kept up to date by the App Store. When the App Store has a new version, the banner says so, and Click Here opens PuggleSlides' page there.

Help ▸ Keyboard shortcuts (⌘/) lists every keyboard shortcut.

## Known limits

- PowerPoint and OpenDocument files with SmartArt or embedded objects open as copies without them, as do videos and sounds linked from the web or from another file instead of embedded. Clips play in the formats macOS plays (MP4, MOV, M4A, MP3, WAV and the like) and can be up to 512 MB each. Videos always stop when the slide changes. PowerPoint files don't keep a clip's fades, bookmarks or full-screen playback, and clips on layouts don't keep how they play. LibreOffice keeps a clip's loop, mute and volume when it saves, but not its start and end times, its hidden icon or whether it stops on slide change.
- Comments have no @mentions, assignments or emoji reactions, since there are no accounts to notify. Files don't keep when a comment was edited, and a PowerPoint comment on a few words of an object's text opens as a comment on the whole object; PowerPoint's assignments and reactions are dropped, and @mentions keep their text. LibreOffice Impress shows replies as comments of their own, and drops threads and resolved marks when it saves.
- Charts can't link to a spreadsheet: their numbers live in the presentation. Word art draws its text straight; PowerPoint's curved and other warped text opens as straight word art.
- OpenDocument has no duotone, so light, dark and sepia recolors are saved as grayscale; guide colors, cell gradients and LibreOffice's own pie slice colors aren't kept. Table cell fills are saved in the form the ODF standard allows, which older versions of LibreOffice may not show.
- 3D charts, pies of pies, radar, stock, bubble and surface charts, stacked lines and charts that combine kinds open in a copy, drawn as the nearest kind PuggleSlides has with their numbers kept. PowerPoint's table styles and LibreOffice's table designs open as the look they give each cell rather than as a style.
- OpenDocument files keep how slides look, with a few simplifications: theme colors and fonts are saved as the colors and fonts they show (so a reopened file keeps its look but Change theme doesn't recolor them), gradients keep their first and last colors, pictures cropped to a shape lose the crop, and text transparency is dropped. LibreOffice's hatch fills open as solid colors, and files with its motion paths, most emphasis effects, embedded objects, media or 3D open as copies without them.
- PowerPoint files keep PuggleSlides' transitions and effects exactly. PowerPoint's many others open as the nearest PuggleSlides has (Wipe as Slide from right, Wheel as Fade, Bounce as Fly in from top and so on). Motion paths, emphasis effects other than Spin, transition sounds, click triggers and automatic timings aren't kept, so files with them open as copies.
- PowerPoint files keep less than they could in a few places: sections, embedded fonts, shadows and other effects, vertical text, tab stops and character spacing aren't kept; line spacing set in points becomes a multiple of the font size; pattern fills become solid; and outlined and square line ends are saved as PowerPoint's nearest (a circle or a diamond).
- Fonts that aren't installed on the Mac (web fonts, for example) show in Arial.
- "Shrink text on overflow" shrinks the text when typing ends rather than while typing.
- Collaborating goes through iCloud, so it needs an iCloud account, for you and for everyone you share with, and a copy of PuggleSlides signed to use it (see Sharing through iCloud); when it can't, the Collaborate sheet says why. When two people change the very same thing at the same moment (both type in one text box or table, move one object, or edit one theme), the change that reaches iCloud last stands. Text being typed goes to the others a moment after each pause, and fitting it to its box happens when typing ends.
- A shared presentation opens from iCloud, so it needs the connection to open, and it's read-only while iCloud can't be reached. A change made just before the connection dropped goes once it's back; closing the presentation before then asks first. Text being typed when the connection drops ends without what hadn't gone yet. While a presentation is shared, its copy in iCloud is the one that counts: the file on the owner's Mac follows it, and changes made to that file in other apps are replaced.
- Notifications reach people once they've opened the shared presentation in PuggleSlides, and macOS asks once whether PuggleSlides may show them. Sharing a presentation clears its undo history up to then. Comments on a slide someone deletes go with it, and come back if the deletion is undone.
- Installing an update takes an administrator's password, so someone who can't give one keeps the version they have (the banner keeps offering the new one). Version 1.1.1 and earlier don't update themselves: the first version that does has to be installed by hand.
- Updates go where the installer puts PuggleSlides, the Applications folder. A copy moved somewhere else stays as it is, and the new version opens from Applications.

## Requirements

- macOS 14 Sonoma or later
- Xcode 26 or later (developed with Xcode 27.2, Swift 6)

## Building and running

Open `PuggleSlides.xcodeproj` in Xcode and run the **PuggleSlides** scheme. Or, from the command line:

```sh
xcodebuild -project PuggleSlides.xcodeproj -scheme PuggleSlides -configuration Debug \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/PuggleSlides.app
```

The app is sandboxed. The update installer inside it (`UpdateInstaller.xpc`, built by the UpdateInstaller target) isn't, since it installs updates in /Applications, which the sandbox can't change. Debug builds are signed to run on the Mac that built them, unless `Config/Signing.xcconfig` names a team (see Sharing from Xcode below), which signs the update installer too (`Config/UpdateInstaller.xcconfig`); releases are signed by `Tools/make-installer.sh`. Debug builds don't update themselves.

### Installer

```sh
Tools/make-installer.sh
```

This builds `build/PuggleSlides.pkg`, which installs PuggleSlides.app in /Applications for all users (macOS asks for an administrator's password). The app runs on Apple silicon and Intel Macs with macOS 14 or later.

A local build is ad-hoc signed and the installer is unsigned. That's fine on the Mac that built it, but a copy that arrives by download, email or AirDrop is blocked the first time: the user has to click **Open Anyway** in System Settings ▸ Privacy & Security. To sign with a Developer ID and have Apple notarize the installer, set the variables described at the top of `Tools/make-installer.sh` before running it. Releases built on GitHub are signed and notarized this way when the repository has the Developer ID secrets (see below).

### Releasing a new version

Versions are MAJOR.MINOR.FIX. To release the next one, run this on `main`, up to date with GitHub and with everything committed:

```sh
Tools/release.sh            # a fix:          1.2.3 → 1.2.4
Tools/release.sh minor      # a minor update: 1.2.3 → 1.3.0
Tools/release.sh major      # a major update: 1.2.3 → 2.0.0
```

The script raises the version and the build number in the Xcode project, commits "Release version 1.2.4", tags it `v1.2.4` and pushes both. The tag starts the Release workflow on GitHub, which runs the package tests, builds the installer with `Tools/make-installer.sh` and publishes it as a GitHub release. The installer keeps the same name in every release, so https://github.com/StaticPrime/PuggleSlides/releases/latest/download/PuggleSlides.pkg always downloads the newest one. `Tools/release.sh --dry-run` shows the next version without changing anything.

Each release also gets `update.json`, which describes the installer (its version, build, minimum macOS, address, size and SHA-256). PuggleSlides reads https://github.com/StaticPrime/PuggleSlides/releases/latest/download/update.json as it opens, to find new versions. Only a signed and notarized release can update copies already installed: the update installer turns down anything else.

To sign and notarize releases, add these secrets under the repository's Settings ▸ Secrets and variables ▸ Actions. Without them, releases are published unsigned, with a warning on the run.

| Secret | What it holds |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | A .p12 file with the "Developer ID Application" and "Developer ID Installer" certificates and their private keys, base64-encoded (`base64 -i DeveloperID.p12 \| pbcopy`) |
| `DEVELOPER_ID_P12_PASSWORD` | The .p12 file's password |
| `NOTARY_API_KEY` | The text of an App Store Connect API key file (`AuthKey_….p8`), used to notarize |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The issuer ID shown above the keys in App Store Connect |
| `DEVELOPER_ID_PROFILE_BASE64` | The Developer ID provisioning profile for iCloud, base64-encoded (see below), which released copies need to collaborate. A signed release stops without it |

### Sharing through iCloud

Shared presentations are kept in iCloud, in the container `iCloud.com.pugglesoft.PuggleSlides`, so only a copy of PuggleSlides signed for that container can share them. Any other copy, like one built from a fresh clone, says so in the Collaborate sheet; debug runs can collaborate through a stand-in for iCloud on the Mac instead (see Tests). To set it up, once:

1. In the Apple Developer account, under Certificates, Identifiers & Profiles ▸ Identifiers, register the iCloud container `iCloud.com.pugglesoft.PuggleSlides`. Then edit the App ID `com.pugglesoft.PuggleSlides`: turn on iCloud, with CloudKit and that container, and Push Notifications.
2. Under Profiles, make a Developer ID provisioning profile for that App ID and the Developer ID Application certificate, and download it.
3. Make the container's schema. iCloud's development environment adds record types as they're first saved, but production only takes what's deployed to it. Either collaborate once from Xcode in the development environment with two iCloud accounts (see Sharing from Xcode below), or add the types by hand in CloudKit Console's development environment, then deploy the schema to production. The types are the same as PuggleDocs', so its schema can be copied as it is (`xcrun cktool export-schema` from PuggleDocs' container, then `xcrun cktool import-schema` into this one):

   | Record type | Fields |
   | --- | --- |
   | `Document` | `info` (Bytes), `revision` (Int64), `snapshot` (Asset) |
   | `Change` | `revision` (Int64), `changeID` (String), `author` (String), `authorName` (String), `change` (Bytes), `changeFile` (Asset, for very large changes like an added video) |
   | `Comment` | `info` (Bytes) |
   | `Presence` | `info` (Bytes) |
   | `Notice` | `title`, `body`, `document`, `owner`, `author` (all String); give `recordName` a Queryable index, without which iCloud turns down the subscription that shows notices |

   iCloud's own record of a share, `cloudkit.share`, only appears in the development schema once a share has been saved there, so share one presentation in the development environment before deploying.
4. Add the profile to the repository as the secret `DEVELOPER_ID_PROFILE_BASE64` (`base64 -i PuggleSlides.provisionprofile | pbcopy`). To build a signed installer on your Mac instead, set `DEVELOPER_ID_PROFILE` to the profile's path along with the Developer ID variables before running `Tools/make-installer.sh`.

`Tools/make-installer.sh` then puts the profile inside the app and signs it for the container, the production environment and pushes. To try collaborating, install it on two Macs signed in to different iCloud accounts.

#### Sharing from Xcode

A debug build can collaborate too, once it's signed with the team. Make `Config/Signing.xcconfig` (Git ignores it) with your team's ID:

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
CODE_SIGN_ENTITLEMENTS = Config/iCloud.entitlements
```

Add an Apple ID in that team under Xcode ▸ Settings ▸ Accounts, then build: Xcode makes the development certificate and provisioning profile itself (the App ID needs iCloud and Push Notifications turned on first, as in step 1). If Xcode can't sign in to that Apple ID, make a macOS App Development provisioning profile for the App ID on the developer website, put it in `~/Library/Developer/Xcode/UserData/Provisioning Profiles`, and add `CODE_SIGN_STYLE = Manual` and `PROVISIONING_PROFILE_SPECIFIER = PuggleSlides Development` (the profile's name) to the file. Set the team in that file rather than under *Signing & Capabilities*, which would write it into the project for everyone. Debug builds use iCloud's production environment, as installed copies do, so a presentation shared from Xcode reaches someone who installed PuggleSlides. Production only takes the kinds of records already deployed to it: when PuggleSlides starts saving a new kind, and once at the start, add `ICLOUD_ENVIRONMENT = Development` to `Config/Signing.xcconfig`, collaborate on a presentation, deploy the schema to production in CloudKit Console, and take the line out again. `Config/iCloud.entitlements` is `PuggleSlides/PuggleSlides.entitlements` with iCloud's added, so keep the two alike.

While debug builds use the development environment, everyone collaborating has to run a debug build too, since installed copies use production: another Mac building from Xcode with the same `Config/Signing.xcconfig` (Xcode registers it the first time), or a second account on the same Mac, signed in to another iCloud account, running a copy of the debug build. In a fresh development environment the first summary notification someone is sent adds the kind of record notifications need, so it isn't shown; the ones after it are. Anything iCloud turns down is written to the Mac's log under the Collaboration category, which Xcode's console shows.

## Tests

The presentation model, inheritance, themes, shape geometry, motion, find and replace, file formats and the engine that keeps shared presentations the same on every Mac live in a Swift package with 317 unit tests, including round trips of every theme, element, table, chart, comment, video and sound, transition and animation through PowerPoint and OpenDocument files, hundreds of randomly damaged files that must never crash the readers, and three simulated Macs making hundreds of random edits at the same time (slides and objects added, moved, deleted, restyled and typed in) through a shared presentation's log and always ending the same. The update check lives there too, with 22 tests of its own (versions, `update.json`, the App Store's answer, when to install, the installer's progress and who signed a package), among them the command that installs updates, run without an administrator, which turns down a package its developer didn't sign:

```sh
cd Packages/PuggleSlidesKit && swift test
```

Debug builds also include an end-to-end check that drives a real window with real key and mouse events and prints `SELFTEST PASS/FAIL` lines. It covers typing into placeholders, the typing settings (smart quotes, smart dashes, capitals and spelling, in text boxes and speaker notes, changes reaching text being typed, macOS's own capitals kept out), new slides and layouts, rich text and lists, drawing, moving, resizing and rotating shapes (with the handles, the arrow keys and the menus), yellow adjustment handles, colors and borders, text boxes that grow, copy and paste, groups, order and alignment, paint format, slide operations, speaker notes, backgrounds, slide numbers, page setup, themes, images, the slideshow, zoom, PowerPoint files, transitions and animations with their undo, the animation timeline, the slideshow playing them, presenter view, grid view, printing, PDF, plain text, SVG and pictures of slides, tables (typing, Tab, selecting, filling, borders, merging, rows and columns, resizing), word art, charts, cropping, masks, recolors and adjustments, guides and snapping, rulers, importing slides, the theme builder and its undo, how tables, charts and word art come through files and downloads, comments (writing, replying, editing, resolving, the panel and the column, undo, files), find and replace (matches, marks, Replace, Replace all, regular expressions, undo), VoiceOver's view of slides and the filmstrip, the focus keys, videos and sounds (inserting real files, refusing ones that won't play, playback settings and their undo, playing on the slide, and playing automatically, on click and manually in slideshows), and that every menu command has something to carry it out:

```sh
build/DerivedData/Build/Products/Debug/PuggleSlides.app/Contents/MacOS/PuggleSlides -PPSelfTest YES
```

A second suite checks collaboration end to end on a stand-in for iCloud, with simulated people on other "Macs": sharing a presentation (saved first), inviting one person to edit and one to comment, their Mac opening it with the same slides, edits both ways, a slide added here, typing in a text box reaching them before editing ends and finishing as one undo step, an object moved here while they type in it, different objects changed at once, slides added on both Macs at once, undo and redo taking back only this Mac's change, the badges and who's viewing (also when iCloud doesn't name people), comments, replies and resolving both ways (and undoing a resolve keeping a reply that came meanwhile), people editing only their own comments, taking someone down to commenting (their changes turned down, their comments still arriving), one summary notification after a quiet spell and a fresh one for what's new since, going offline (read-only with a note saying so, text being typed ending without what hadn't gone, editing, commenting and undo changing nothing, nothing waiting to be sent, and catching up once iCloud's back, a comment made meanwhile included), the theme builder's changes reaching them as one undo step, renaming, stopping sharing (the presentation kept here, gone for the others), a big pasted picture arriving whole, a presentation someone else shares opening to comment on (comments allowed, edits changing nothing, their edits, comments, pictures and renames arriving live, a change iCloud passes over while reading still arriving with the ones after it, presenting, printing, downloading and copying allowed, and the window saying so and closing when they stop sharing), one opened while offline waiting until iCloud can be reached, and invitation links:

```sh
build/DerivedData/Build/Products/Debug/PuggleSlides.app/Contents/MacOS/PuggleSlides -PPSelfTest YES -PPSelfTestSuite collaboration
```

Other debug launch arguments: `-PPSampleDocument YES` fills new presentations with a sample deck that uses every layout, lists, shapes, lines, an image, speaker notes, transitions, animations and a skipped slide. `-PPSnapshot name.png` saves a screenshot of the first window (or the splash screen, Settings, the slideshow, the About window or an open dialog) to the app's temporary folder and quits. Combine it with `-PPWindowWidth`, `-PPWindowHeight`, `-PPSlide 4`, `-PPSelect 2` (selects the slide's second element), `-PPEditText YES` (starts editing it), `-PPZoom 2`, `-PPTheme Midnight`, `-PPHideNotes YES`, `-PPSidebar themes` (or `formatOptions`), `-PPOpenSheet shortcuts` (or `background`, `pageSetup`, `slideNumbers`, `link`, or `settings` for the Settings window), `-PPPresent YES` or `-PPPresenterView YES` (with `-PPAdvance 2` to press Next twice and `-PPFreezeMotion 0.5` to stop transitions and animations halfway), `-PPMotionPanel YES`, `-PPGridView YES`, `-PPOpenSheet print` (with `-PPPrintLayout notes` or `handout6` and `-PPPrintLandscape YES`), `-PPSidebar chartEditor` (or `comments`), `-PPComments YES` (adds comments about the selected object and the slide) and `-PPCommentDraft YES` (opens Insert ▸ Comment), `-PPFind walks` (with `-PPFindNext 1`, and `-PPSnapshotPanel YES` to photograph the dialog), `-PPThemeBuilder YES` (with `-PPThemeColors YES`), `-PPCellRange 0,0,1,2` and `-PPEditCell 1,1` (with a table selected), `-PPCrop YES` (with a picture selected), `-PPAddGuides YES`, `-PPShowRuler YES`, `-PPShowAbout YES`, `-PPWriteFile name.pptx` (saves the presentation to the temporary folder), `-PPDownload pdf,svg` (writes File ▸ Download formats there as `download.pdf` and so on) or `-PPOpenFile name.odp` (opens a file from the temporary folder). `-PPBenchmark YES` times thumbnails, drawing and editing on a 300-slide deck. `-PPStandInCloud YES` collaborates through the stand-in for iCloud, and with `-PPCollaborationDemo YES` too the window's presentation is shared with two simulated people who open it, edit and comment (add `-PPOpenSheet collaborate` for the Collaborate sheet, `-PPCollaborationDemoRole commenter` for a presentation someone else shares with this Mac to comment on, or `-PPDemoOffline YES` to show it while iCloud can't be reached).

For updates: `-UpdateDemo splash|downloading|waiting|installing|restarting|banner|appstore` shows that part of updating with made-up values and no network (combine it with `-PPSnapshot`), and `-UpdateDemo relaunch` opens a new copy of the app and quits, as the end of an update does. `-UpdateFeedURL <address of an update.json>` makes a debug build check there (a server on this Mac can serve one over plain HTTP); with `-UpdateDryRun YES` too, the update installer only checks the downloaded package, as it does before asking for a password, then the installation is acted out without the password dialog (nothing is installed) and the app opens a new copy of itself, as it does after a real update. `-UpdateAppStoreBundleID <bundle identifier>` asks the App Store about that app instead, as a copy from the App Store would. `-ShowsSplash NO` opens without the splash screen, as the self-tests, screenshots and the benchmark do. The update check writes what it finds to the Mac's log under the Updates category.

## Project layout

```
PuggleSlides/               macOS app target (files are picked up automatically by Xcode)
  App/                      Entry point, app delegate, debug-only sample and self-tests
  Collaboration/            Sharing through iCloud: each shared presentation's session, iCloud, the Collaborate
                            sheet, the badges, and a stand-in for iCloud for debug runs
  Document/                 PresentationDocument (NSDocument)
  Editor/                   PresentationController: edits and undo, slides, shapes, formatting, tables, images,
                            guides, the theme builder, comments, find and replace, inserting videos and sounds
  Canvas/                   The slide editor: drawing, handles, mouse and keyboard, text editing, text layout,
                            tables, word art, cropping, guides and snapping, find marks, VoiceOver, video
                            posters and speaker icons, speaker notes, SVG export
  Filmstrip/                Slide thumbnails
  Present/                  The slideshow, presenter view, transitions, the animation timeline, and videos and
                            sounds playing
  UI/                       Window controller, SwiftUI header and toolbar, menus, panels (Motion, themes,
                            format options, comments), comment cards, Find and replace, dialogs, print preview
  Updates/                  The splash screen, the update check, download and installation, the banner,
                            Settings
  Resources/                Asset catalog (app icon, About window logo)
UpdateInstaller/            The update installer service (outside the sandbox), inside the app
Packages/PuggleSlidesKit/   Presentation model, themes, shape geometry and file formats (no UI)
  Model/                    Slides, elements, text, colors, fills, themes, layouts, inheritance, transitions
                            and animations, tables, charts, image adjustments, guides, comments, video and
                            audio clips
  Editing/                  New slides, Apply layout, Change theme, slide numbers, importing slides and themes,
                            the theme builder's layout edits, find and replace
  Charts/                   Chart drawing, ported from PuggleSheets
  Fonts/                    Fonts from the system, asked for one at a time
  Geometry/                 DrawingML's shape guide formulas and the shape gallery
  IO/                       ZIP, XML, PowerPoint (.pptx) and OpenDocument (.odp) readers and writers
  Collaboration/            A shared presentation's parts and their changes, order keys, its log, its iCloud
                            records, summaries
  PuggleUpdate/             Updates: versions, update.json, the App Store's answer, the command that
                            installs updates
Config/                     Signing for debug builds (see Sharing from Xcode)
Tools/make-icons.swift      Regenerates the app icon PNGs
Tools/make-installer.sh     Builds the PuggleSlides.pkg installer
Tools/release.sh            Releases the next version (see Releasing a new version)
```

## How it works

- **The model** mirrors PowerPoint's: a theme (a slide master) holds colors, fonts, the background, decorations, text styles for titles, body text and everything else, and the layouts; slides point at a layout. A property that isn't set inherits: a slide's placeholder takes its position, formatting and text fitting from the layout's matching placeholder, then the theme's, then the theme's text styles. That's why changing the theme or the layout restyles text you haven't formatted by hand, and why PowerPoint files round-trip without flattening.
- **Sizes** are points, 1/72 inch: a 16:9 slide is 720 × 405, or 10 × 5.625 inches. "100%" zoom shows a slide at the size a browser does, 96 pixels per inch.
- **Drawing** is one renderer for the canvas, the thumbnails and the slideshow, so they always agree. Shapes come from DrawingML's preset definitions, evaluated with its shape guide formulas, so they match PowerPoint's exactly, adjustment handles included.
- **Text** is laid out with TextKit, the same way for display and for editing, so text doesn't shift when you click into it. A custom layout manager draws bullets and numbers, recounting numbered lists as you type. When editing ends, the text is saved with only the formatting that differs from what it inherits.
- **Motion** is drawn by the same renderer, with each element's opacity, offset, scale and rotation (and each paragraph's, for text by paragraph) worked out from a timeline of click groups ("On click", "After previous" and "With previous"). Transitions blend two pictures of the slides, with Flip and Cube drawn in perspective strip by strip. The slideshow and presenter view share one stage, so they always show the same moment.
- **Printing, PDF and the print preview** share one view that lays out pages, so the preview is exactly what prints.
- **Tables** keep their borders as the lines between cells, so a border is one line however many cells share it. One layout, with rows grown to fit their text, serves drawing, clicking, typing and exporting, and a table's frame follows it.
- **The theme builder** edits a stand-in presentation whose slides are the theme and its layouts; every edit is mapped straight back into the real theme, so the slides, the document and autosave stay current, and the builder keeps its own undo history until it closes.
- **Edits** go through one controller method that records the presentation and the selection before and after, so undo and redo restore exactly what was there. Dragging updates live and records one step when the mouse comes up.
- **Collaboration.** A shared presentation is kept, on every Mac and in iCloud, as parts that each change as a whole: the slide size, the default text styles, the guides, each theme and each layout, six parts per slide (its layout, background, notes, skipping, transition and animations) and three per object (its place, its text, and the rest). Every list (slides, a slide's objects, themes, layouts) gives each item an order key that sorts, so moving or adding an item changes only its own key, and two people adding slides at once both keep theirs. An edit is recorded as the parts it changed, measured from the presentation as it was, and goes into the presentation's log: two zones in its owner's iCloud, the document zone with a snapshot of all the parts now and then and one record per revision, each one change, named for its revision so that only one change can ever take it. Each Mac sends its changes one at a time, claiming the revision after the last it knows; when another Mac got there first, it applies that change, keeping its own where both changed the same part, and sends again. What a Mac shows is always what its parts say, so every Mac ends the same. The document zone is shared with each person as edit or read-only, so iCloud itself refuses changes from people who may only comment. The talk zone, which everyone in the presentation can write to through a link kept in the document zone, holds the comments (each with its slide) and who has it open. Undo keeps, for each edit, the parts it changed and what they were, and puts back only those still as it left them. Each person's Mac also keeps an inbox zone shared by link with the people they work with, who leave a short summary there after a quiet spell; a subscription on it makes iCloud show the notification.
- **PowerPoint and OpenDocument files** are read and written with our own ZIP and XML code. The reader keeps inheritance as it is in the file, resolves PowerPoint's shape styles and color maps, and names exactly what it couldn't keep.
- **Updates.** The splash screen holds back what opening would do (an untitled presentation, presentations opened from the Finder, invitation links, notifications) until the update check is done. The check reads the newest release's `update.json`, with a 5-second limit and nothing cached. A newer version's installer is downloaded into the app's own container and checked against the size and SHA-256 in `update.json`. The sandboxed app can't change /Applications, so it hands the file to the update installer, an XPC service inside the app that runs outside the sandbox and takes connections only from the app it's inside. The service checks that the package is signed with a Developer ID Installer certificate of the same team as itself and that Gatekeeper accepts it (it's notarized), then runs AppleScript's `do shell script … with administrator privileges`, which is where macOS asks for the password. That command, as root, copies the package into a new folder only root can change, checks it again there, and runs macOS's `installer`, whose progress (`installer -verboseR`) the service reads from a log and passes to the "Updating…" bar. Afterwards the service makes sure /Applications holds the version `update.json` named, so a release that doesn't contain what it says can't send PuggleSlides round in circles. The app then closes its presentations (ending any slideshow) and opens a new copy of itself from /Applications, handing it the presentations and links that were waiting, and quits. A copy from the App Store (one with an App Store receipt) instead asks Apple's lookup service for the version the App Store has. An App Store build must leave out the update installer, as the App Store doesn't allow code outside the sandbox.

## Contributing

Bug reports, ideas and pull requests are welcome. Before your first pull request is merged, you sign the [PuggleSoft Contributor License Agreement](CLA.md) by posting one comment, and a bot walks you through it. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Copyright © 2026 PuggleSoft.

PuggleSlides is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3, as published by the Free Software Foundation. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full terms.
