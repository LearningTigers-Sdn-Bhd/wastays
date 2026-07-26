class BookingAuditLog < ApplicationRecord
  CATEGORIES = %w[status stay room financial notes other].freeze

  belongs_to :hotel
  belongs_to :auditable, polymorphic: true
  belongs_to :user, optional: true

  validates :action_type, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :source, :occurred_at, presence: true

  before_update :prevent_update
  before_destroy :prevent_destroy

  def display_auditable_name
    case auditable_type
    when "Booking"
      "Booking"
    when "BookingQuote"
      "Quote"
    when "BookingRoom"
      "Room Assignment"
    else
      auditable_type.titleize
    end
  end

  def action_label
    case action_type
    when "create" then "Created"
    when "update" then "Updated"
    when "status_change" then "Status Changed"
    when "check_in" then "Checked In"
    when "undo_check_in" then "Undo Check-in"
    when "check_out" then "Checked Out"
    when "cancel" then "Cancelled"
    when "void" then "Voided"
    when "reinstate" then "Reinstated"
    when "convert" then "Converted from Quote"
    when "note_added" then "Note Added"
    when "charge_added" then "Charge Added"
    when "payment_recorded" then "Payment Recorded"
    when "pre_checkin_completed" then "Pre-Check-in Completed"
    else action_type.titleize
    end
  end

  def action_icon
    case action_type
    when "create" then "plus"
    when "update" then "pencil"
    when "status_change" then "refresh-cw"
    when "check_in" then "log-in"
    when "undo_check_in" then "rotate-ccw"
    when "check_out" then "log-out"
    when "cancel" then "circle-x"
    when "void" then "circle-slash"
    when "reinstate" then "rotate-ccw"
    when "convert" then "file-text"
    when "note_added" then "message-square"
    when "charge_added" then "receipt"
    when "payment_recorded" then "credit-card"
    when "pre_checkin_completed" then "badge-check"
    else "activity"
    end
  end

  def action_color
    case action_type
    when "create" then "text-blue-600 bg-blue-50"
    when "check_in", "pre_checkin_completed" then "text-emerald-600 bg-emerald-50"
    when "undo_check_in" then "text-amber-600 bg-amber-50"
    when "check_out" then "text-slate-600 bg-slate-50"
    when "cancel", "void" then "text-rose-600 bg-rose-50"
    when "reinstate" then "text-amber-600 bg-amber-50"
    when "payment_recorded", "charge_added" then "text-indigo-600 bg-indigo-50"
    else "text-slate-600 bg-slate-50"
    end
  end

  def formatted_changes
    # Returns an array of hashes { field: "Name", old: "Value", new: "Value" }
    return [] unless new_value.is_a?(Hash)

    changes = []
    # Ensure old_value is a hash for safe access, even if it was nil or something else
    old_val_hash = old_value.is_a?(Hash) ? old_value : {}

    new_value.each do |field, new_val|
      old_val = old_val_hash[field]
      next if old_val == new_val

      changes << {
        field: field.titleize,
        old: format_value(old_val),
        new: format_value(new_val)
      }
    end
    changes
  end

  def display_value_change
    formatted_changes.map { |c| "#{c[:field]}: #{c[:old]} -> #{c[:new]}" }.join(", ")
  end

  private

  def prevent_update
    errors.add(:base, "Booking audit logs are immutable.")
    throw :abort
  end

  def prevent_destroy
    errors.add(:base, "Booking audit logs are immutable and cannot be deleted.")
    throw :abort
  end

  def format_value(value)
    case value
    when NilClass
      "N/A"
    when TrueClass
      "Yes"
    when FalseClass
      "No"
    when Hash
      format_hash(value)
    when Array
      format_array(value)
    else
      value.to_s
    end
  end

  def format_hash(hash)
    return "{}" if hash.blank?

    # If it's a large object like a snapshot, just summarize it
    if hash.keys.size > 5
      return "{ #{hash.keys.first(3).map(&:to_s).map(&:titleize).join(', ')} ... }"
    end

    hash.map { |k, v| "#{k.to_s.titleize}: #{format_value(v)}" }.join(", ")
  end

  def format_array(array)
    return "[]" if array.blank?

    # If it's an array of objects (like tax_lines), summarize
    if array.all? { |e| e.is_a?(Hash) }
      return "#{array.size} items"
    end

    array.map { |e| format_value(e) }.join(", ")
  end
end
