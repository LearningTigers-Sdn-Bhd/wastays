class Public::RegistrationsController < ApplicationController
  layout "auth"
  helper_method :invite_agent

  def new
    @user = User.new
    @account = Account.new
    @hotel = Hotel.new
    @wizard_start_step = 1
  end

  def create
    result = HotelOps::CreateHotel.new(
      account_params: account_params,
      user_params: user_params,
      hotel_params: invited_hotel_params,
      agent: invite_agent
    ).call

    if result[:success]
      SuperAgentMailer.hotel_registered(result[:hotel]).deliver_later if invite_agent
      sign_in_user(result[:user])
      redirect_to hotel_dashboard_path(result[:hotel]), notice: "Welcome! Your hotel account has been created."
    else
      flash.now[:alert] = result[:error]
      @user = User.new(user_params)
      @account = Account.new(account_params)
      @hotel = Hotel.new(hotel_params)
      copy_invalid_errors(result[:invalid_record])
      @wizard_start_step = wizard_step_for(result[:invalid_record])
      render :new, status: :unprocessable_content
    end
  end

  private

  # A hotel that registers from a super agent invite link (?c=CODE) joins that
  # agent: it gets the agent hotel defaults and the agent can open it. An
  # unknown code is ignored, so the hotel still registers as normal.
  def invite_agent
    return @invite_agent if defined?(@invite_agent)

    code = params[:c].to_s.strip.upcase
    @invite_agent = (User.super_agents.find_by(agent_code: code) if code.present?)
  end

  def invited_hotel_params
    return hotel_params unless invite_agent

    hotel_params.to_h.symbolize_keys.merge(SuperAgents::HotelDefaults.call)
  end

  def copy_invalid_errors(invalid_record)
    return unless invalid_record

    target = { Account => @account, Hotel => @hotel, User => @user }[invalid_record.class]
    target&.errors&.copy!(invalid_record.errors)
  end

  def wizard_step_for(invalid_record)
    { Account => 1, Hotel => 2, User => 3 }.fetch(invalid_record.class, 1)
  end

  def account_params
    params.require(:account).permit(:name)
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  def hotel_params
    params.require(:hotel).permit(:name, :city, :country, :sell_mode)
  end
end
