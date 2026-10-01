# frozen_string_literal: true

module Admin
  class SuperAgentsController < Admin::BaseController
    include SheetActionCompletion

    def index
      @agents = current_user.account.users.where(role: "super_agent").includes(:created_hotels).order(:name)
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

    def destroy
      agent = current_user.account.users.where(role: "super_agent").find(params[:id])
      agent.destroy!
      redirect_to admin_super_agents_path, notice: "Super agent removed.", status: :see_other
    end

    private

    def agent_params
      params.fetch(:user, {}).permit(:name, :email, :password)
    end
  end
end
