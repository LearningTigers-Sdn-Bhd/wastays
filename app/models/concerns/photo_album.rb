# frozen_string_literal: true

# An album of photos where one of them leads. The featured photo is the one
# guests meet first — the card on the search results, the cover on the room row —
# so the property picks it rather than the upload order picking it for them.
#
# Shared by Hotel and RoomType. Both own an album, and both hand one photo to
# the page that sells them.
module PhotoAlbum
  extend ActiveSupport::Concern

  included do
    validate :featured_photo_attachment_belongs_to_album
  end

  # Read from the loaded attachments, not with a find_by. A page that renders
  # many albums already loads them, and a query for each cover would be one more
  # query per hotel on the search results.
  def featured_photo_attachment
    return nil if featured_photo_attachment_id.blank?

    photos.attachments.find { |attachment| attachment.id == featured_photo_attachment_id }
  end

  # The album in the order guests read it: the featured photo first, then the
  # order the property arranged. The featured photo never appears in
  # photo_order, so featuring another photo cannot disturb the saved sequence.
  def ordered_photo_attachments
    featured = featured_photo_attachment
    rest = photos.attachments.to_a.reject { |attachment| attachment.id == featured&.id }

    featured.present? ? [ featured ] + sort_album_photos(rest) : sort_album_photos(rest)
  end

  # An album with photos always has a featured one. Nobody has to think about
  # choosing the first one, and a setup step can ask for a photo rather than for
  # a photo plus a separate decision about it. Picking a different featured photo
  # later still works — this only fills a gap, it never overrides a choice.
  def feature_first_photo
    return if featured_photo_attachment_id.present?

    first_photo = photos.attachments.order(:id).first
    return if first_photo.blank?

    update_column(:featured_photo_attachment_id, first_photo.id)
  end

  # Removing the featured photo does not leave the album without one. The
  # remaining photos promote their own replacement, so "has photos" and "has a
  # featured photo" never come apart. Callers purge after this runs, so the
  # promoted attachment is chosen from what will still be there.
  def promote_featured_photo_before_removing(photo_ids)
    return if featured_photo_attachment_id.blank?

    removed_ids = Array(photo_ids).map(&:to_i)
    return unless removed_ids.include?(featured_photo_attachment_id.to_i)

    successor = photos.attachments.where.not(id: removed_ids).order(:id).first
    update_column(:featured_photo_attachment_id, successor&.id)
  end

  # Stores the sequence of the photos behind the featured one. Unknown ids and
  # the featured id are dropped, so a stale form cannot write a broken order.
  def reorder_photos!(attachment_ids)
    known_ids = photos.attachments.pluck(:id)
    ordered = Array(attachment_ids).map(&:to_i)
                                   .uniq
                                   .select { |id| known_ids.include?(id) }
                                   .reject { |id| id == featured_photo_attachment_id.to_i }

    # Written straight to the column, the way the featured photo is. The album
    # order is not something the property fills in, so an unrelated stale field
    # must not be able to block it.
    update_column(:photo_order, ordered)
  end

  private

  # The order the property arranged. Photos uploaded after the last save have no
  # saved position, so they follow the ordered ones by upload order.
  def sort_album_photos(attachments)
    positions = photo_order.each_with_index.to_h
    attachments.sort_by { |attachment| [ positions[attachment.id] || Float::INFINITY, attachment.id ] }
  end

  def featured_photo_attachment_belongs_to_album
    return if featured_photo_attachment_id.blank?
    return if photos.attachments.any? { |attachment| attachment.id == featured_photo_attachment_id }

    errors.add(:featured_photo_attachment_id, "must belong to this #{model_name.human.downcase}")
  end
end
