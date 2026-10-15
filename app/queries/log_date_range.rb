# frozen_string_literal: true

# Turns the "start/end" value of a PanelsUI range picker into a time range.
# Either end can be missing. A bad date counts as missing.
class LogDateRange
  def self.call(value)
    start_date, end_date = value.to_s.split("/", 2).map { |part| parse(part) }
    return unless start_date || end_date

    start_date&.beginning_of_day..end_date&.end_of_day
  end

  def self.parse(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
  private_class_method :parse
end
