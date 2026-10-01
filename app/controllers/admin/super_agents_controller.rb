# frozen_string_literal: true

module Admin
  class SuperAgentsController < Admin::BaseController
    include SheetActionCompletion

    def index
      @agents = current_user.account.users.super_agents.includes(:created_hotels).order(:name)
    end

    def new
      @agent = User.new
    end

    def create
      result = Admin::SuperAgents::CreateService.new(account: current_user.account, params: agent_params).call

      if result.success?
        flash[:agent_credentials] = { "email" => result.agent.email, "password" => result.password }
        complete_sheet_action(destination: admin_super_agents_path, notice: "Super agent created.", frame: "admin_super_agent_action_sheet")
      else
        @agent = result.agent
        render :new, status: :unprocessable_content
      end
    end

    # The table switch for one agent: may they create hotels themselves?
    def update
      agent = current_user.account.users.super_agents.find(params[:id])
      agent.update!(can_create_hotels: params.dig(:user, :can_create_hotels) == "1")

      notice = agent.can_create_hotels? ? "#{agent.name} can now create hotels." : "#{agent.name} can no longer create hotels."
      redirect_to admin_super_agents_path, notice: notice, status: :see_other
    end

    def destroy
      agent = current_user.account.users.super_agents.find(params[:id])
      agent.destroy!
      redirect_to admin_super_agents_path, notice: "Super agent removed.", status: :see_other
    end

    private

    def agent_params
      params.fetch(:user, {}).permit(:name, :email, :password)
    end
  end
end
