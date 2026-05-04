module PhoneIdentity
  module_function

  def variants(raw)
    digits = digits_only(raw)
    return [] if digits.blank?

    if digits.start_with?("60")
      local = digits.sub(/\A60/, "0")
      [ "+#{digits}", digits, local ]
    elsif digits.start_with?("0")
      [ digits, "60#{digits[1..]}", "+60#{digits[1..]}" ]
    else
      [ digits, "0#{digits}", "+60#{digits}", "60#{digits}" ]
    end.uniq
  end

  def canonical(raw)
    variants(raw).first.to_s
  end

  def digits_only(raw)
    raw.to_s.gsub(/\D/, "")
  end

  def booking_lookup_suffix(raw, length: 9)
    digits = digits_only(raw)
    return "" if digits.blank?

    digits.last(length)
  end

  def find_guest(raw)
    variants(raw).each do |variant|
      guest = Guest.find_by(phone: variant)
      return guest if guest
    end

    nil
  end
end
