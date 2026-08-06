module FilteringHelper
  def date_preset_options(include_single: false, as_of: false)
    options = [
      [ "Today", "today" ],
      [ "This Month", "this_month" ],
      [ "Last Month", "last_month" ]
    ]
    options.concat([ [ "This Year", "this_year" ], [ "All Time", "all_time" ] ]) unless as_of

    # Add last 6 months specifically
    (0..5).each do |i|
      date = i.months.ago.to_date
      val = date.strftime("%Y-%m")
      label = date.strftime("%B %Y")
      options << [ label, val ] unless options.any? { |o| o[1] == val }
    end

    options << [ "Single Date", "single" ] if include_single
    options << [ as_of ? "Custom Date" : "Custom Range", "custom" ]
    options
  end
end
