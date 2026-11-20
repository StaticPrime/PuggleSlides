import AppKit
import PuggleSlidesKit

/// Image tools (crop, mask, reset, replace and adjustments) and guides.
extension PresentationController {
    /// The one selected element, when it's a picture.
    var selectedPicture: SlideElement? {
        guard selectedElementIDs.count == 1, let element = selectedElements.first, element.picture != nil else { return nil }
        return element
    }

    var selectedChart: SlideElement? {
        guard selectedElementIDs.count == 1, let element = selectedElements.first, element.chart != nil else { return nil }
        return element
    }

    private func editPicture(_ actionName: String, _ change: @escaping (inout Picture, inout SlideElement) -> Void) {
        guard let id = selectedPicture?.id else { return }
        editElements([id], actionName) { element, _ in
            guard var picture = element.picture else { return }
            change(&picture, &element)
            element.picture = picture
        }
    }

    /// Mask image: cuts the picture to a shape from the gallery.
    func maskSelectedImage(_ preset: String) {
        editPicture("Mask Image") { picture, _ in
            picture.geometry = .preset(preset, adjustments: PresetGeometry.defaultAdjustments(preset))
        }
    }

    /// Reset image: no crop, mask or adjustments, at the picture's own proportions (keeping its width and center).
    func resetSelectedImage() {
        guard let element = selectedPicture, let picture = element.picture else { return }
        let image = ImageCache.shared.image(picture.mediaID, in: presentation)
        editPicture("Reset Image") { picture, element in
            picture.crop = .none
            picture.geometry = .rectangle
            picture.adjustments = .none
            if let image, image.size.width > 0, var placement = element.placement {
                let frame = placement.frame
                let height = abs(frame.width) * Double(image.size.height / image.size.width)
                placement.frame = SlideRect(x: frame.x, y: frame.midY - height / 2, width: frame.width, height: height)
                placement.rotation = 0
                placement.flipHorizontal = false
                placement.flipVertical = false
                element.placement = placement
            }
        }
    }

    /// Replace image: a new picture in the same place and size, keeping the mask, border and adjustments.
    /// The crop is cleared, since it belonged to the old picture.
    func replaceSelectedImage(with original: Data) -> Bool {
        guard let id = selectedPicture?.id, let (data, contentType) = MediaItem.storable(original), NSImage(data: data) != nil,
              let slideIndex = currentSlideIndex else { return false }
        perform("Replace Image") { presentation in
            let mediaID = presentation.addMedia(data, contentType: contentType)
            guard let index = presentation.slides[slideIndex].elementIndex(id: id), var picture = presentation.slides[slideIndex].elements[index].picture else { return }
            picture.mediaID = mediaID
            picture.crop = .none
            presentation.slides[slideIndex].elements[index].picture = picture
            presentation.removeUnusedMedia()
        }
        return true
    }

    /// Format options ▸ Adjustments and Recolor.
    func setImageAdjustments(_ actionName: String, _ change: @escaping (inout ImageAdjustments) -> Void) {
        editPicture(actionName) { picture, _ in change(&picture.adjustments) }
    }

    /// Commits a crop made on the canvas: the crop and the frame it leaves.
    func setCrop(_ crop: ImageCrop, frame: SlideRect, for id: UUID) {
        editElements([id], "Crop Image") { element, _ in
            guard var picture = element.picture, var placement = element.placement else { return }
            picture.crop = crop
            placement.frame = frame
            element.picture = picture
            element.placement = placement
        }
    }

    // MARK: Charts

    func editChart(_ actionName: String, id: UUID? = nil, _ change: @escaping (inout Chart) -> Void) {
        guard let id = id ?? selectedChart?.id else { return }
        editElements([id], actionName) { element, _ in
            guard var chart = element.chart else { return }
            change(&chart)
            element.chart = chart
        }
    }

    // MARK: Guides

    /// View ▸ Guides ▸ Add vertical (or horizontal) guide: through the middle of the slide.
    @discardableResult
    func addGuide(_ orientation: Guide.Orientation, at position: Double? = nil) -> UUID {
        let size = presentation.slideSize
        let guide = Guide(orientation: orientation, position: position ?? (orientation == .vertical ? size.width / 2 : size.height / 2))
        perform("Add Guide", update: [.content]) { presentation in presentation.guides.append(guide) }
        return guide.id
    }

    func setGuides(_ guides: [Guide], actionName: String = "Edit Guides") {
        perform(actionName, update: [.content]) { presentation in presentation.guides = guides }
    }

    func deleteGuide(_ id: UUID) {
        perform("Delete Guide", update: [.content]) { presentation in presentation.guides.removeAll { $0.id == id } }
    }

    func clearGuides() {
        guard !presentation.guides.isEmpty else { return }
        perform("Clear Guides", update: [.content]) { presentation in presentation.guides = [] }
    }
}
