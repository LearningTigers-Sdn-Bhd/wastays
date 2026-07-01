module FilteringHelper
  def date_preset_options
    options = [
      [ "Today", "today" ],
      [ "This Month", "this_month" ],
      [ "Last Month", "last_month" ],
      [ "This Year", "this_year" ],
      [ "All Time", "all_time" ]
    ]

    # Add last 6 months specifically
    (0..5).each do |i|
      date = i.months.ago.to_date
      val = date.strftime("%Y-%m")
      label = date.strftime("%B %Y")
      options << [ label, val ] unless options.any? { |o| o[1] == val }
    end

    options << [ "Custom Range", "custom" ]
    options
  end
end
