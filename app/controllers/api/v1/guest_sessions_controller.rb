class Api::V1::GuestSessionsController < Api::V1::BaseController
  def create
    phone = normalize_phone(params[:phone])

    if phone.blank?
      render json: { error: "phone is required" }, status: :bad_request
      return
    end

    guest = ::Guest.find_by(phone: phone)

    unless guest
      render json: { error: "No guest found with that phone number" }, status: :not_found
      return
    end

    otp   = guest.generate_otp!
    token = guest.generate_magic_token!

    render json: {
      guest_name: guest.name,
      otp_code: otp,
      magic_link: guest_verify_url(token: token),
      expires_in_seconds: ::Guest::OTP_EXPIRY.to_i
    }
  end

  private

  def find_guest_by_phone(raw)
    digits = raw.to_s.gsub(/\D/, "")
    return nil if digits.blank?

    variants = []
    if digits.start_with?("60")
      local = digits.sub(/\A60/, "0")
      variants = [ "+#{digits}", digits, local ]
    elsif digits.start_with?("0")
      variants = [ digits, "60#{digits[1..]}", "+60#{digits[1..]}" ]
    else
      variants = [ digits, "0#{digits}", "+60#{digits}", "60#{digits}" ]
    end

    variants.each do |v|
      guest = ::Guest.find_by(phone: v)
      return guest if guest
    end
    nil
  end

  def normalize_phone(raw)
    return "" if raw.blank?
    digits = raw.to_s.gsub(/\D/, "")
    # 60xxxxxxxx → +60xxxxxxxx, 0xxxxxxxx → +60xxxxxxxx
    if digits.start_with?("60")
      "+#{digits}"
    elsif digits.start_with?("0")
      "+6#{digits}"
    else
      "+#{digits}"
    end
  end
end
