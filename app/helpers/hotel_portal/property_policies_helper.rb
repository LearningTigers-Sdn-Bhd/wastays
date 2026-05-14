module HotelPortal::PropertyPoliciesHelper
  def hotel_time_options
    (0..23).flat_map do |hour|
      [0, 15, 30, 45].map do |minute|
        time = Time.current.change(hour: hour, min: minute)
        label = time.strftime("%I:%M %p")
        [label, label]
      end
    end
  end
end
