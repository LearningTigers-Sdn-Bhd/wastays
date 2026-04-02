class InventoryAuditLog < ApplicationRecord
  belongs_to :hotel
  belongs_to :room_type, optional: true
  belongs_to :user

  validates :action_type, presence: true

  def display_details
    room_type&.name || "Property-wide"
  end

  def display_value_change
    change_date = old_value["date"].presence || new_value["date"].presence

    case action_type
    when "bulk_rate_update", "rate_update"
      "#{format_change_date(change_date)}#{format_rate_value(old_value)} -> #{format_rate_value(new_value)}"
    when "bulk_inventory_update", "inventory_update"
      "#{format_change_date(change_date)}#{format_inventory_value(old_value)} -> #{format_inventory_value(new_value)}"
    else
      "#{format_change_date(change_date)}#{format_generic_value(old_value)} -> #{format_generic_value(new_value)}"
    end
  end

  private

  def format_rate_value(value)
    currency = value["currency"].presence || new_value["currency"].presence || "MYR"
    amount = value["price"]

    return "N/A" if amount.nil?

    "#{currency} #{amount}"
  end

  def format_inventory_value(value)
    quantity = value["quantity"]
    status = value["status"].presence || "n/a"

    [
      (quantity.nil? ? "Qty N/A" : "Qty #{quantity}"),
      status.to_s.titleize
    ].join(" / ")
  end

  def format_generic_value(value)
    return "N/A" if value.blank?

    value.to_json
  end

  def format_change_date(date)
    date.present? ? "#{date}: " : ""
  end
end
