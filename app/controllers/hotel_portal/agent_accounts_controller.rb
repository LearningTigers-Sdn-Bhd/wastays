# frozen_string_literal: true

module HotelPortal
  class AgentAccountsController < BaseController
    before_action :set_agent_account, only: %i[edit update destroy]

    def index
      authorize AgentAccount
      @agent_accounts = policy_scope(AgentAccount).where(hotel: current_hotel).order(name: :asc)
    end

    def new
      @agent_account = current_hotel.agent_accounts.build
      authorize @agent_account
    end

    def edit
    end

    def create
      @agent_account = current_hotel.agent_accounts.build(agent_account_params)
      authorize @agent_account

      if @agent_account.save
        redirect_to hotel_portal_agent_accounts_path, notice: "Agent Account was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @agent_account.update(agent_account_params)
        redirect_to hotel_portal_agent_accounts_path, notice: "Agent Account was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @agent_account.destroy
      redirect_to hotel_portal_agent_accounts_path, notice: "Agent Account was successfully deleted."
    end

    private

    def set_agent_account
      @agent_account = current_hotel.agent_accounts.find(params[:id])
      authorize @agent_account
    end

    def agent_account_params
      params.require(:agent_account).permit(:name, :account_type, :contact_email, :contact_phone)
    end
  end
end
