class BookingAuditLog < ApplicationRecord
  belongs_to :hotel
  belongs_to :auditable, polymorphic: true
  belongs_to :user, optional: true

  validates :action_type, presence: true

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

  def display_value_change
    # Generic display of changes from old_value to new_value
    # Expecting old_value and new_value to be hashes of { field_name: value }

    changes = []

    new_value.each do |field, new_val|
      old_val = old_value[field]
      next if old_val == new_val

      changes << "#{field.titleize}: #{format_value(old_val)} -> #{format_value(new_val)}"
    end

    changes.join(", ")
  end

  private

  def format_value(value)
    case value
    when NilClass
      "N/A"
    when TrueClass
      "Yes"
    when FalseClass
      "No"
    when Hash, Array
      value.to_json
    else
      value.to_s
    end
  end
end
