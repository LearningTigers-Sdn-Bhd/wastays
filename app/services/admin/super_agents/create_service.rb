# frozen_string_literal: true

module Admin
  module SuperAgents
    # Creates a super agent in the platform account. The superadmin can type a
    # password or leave it empty to get a generated one. Either way the agent
    # can sign in at once, and the superadmin sees the password once.
    class CreateService
      Result = Struct.new(:success?, :agent, :password)

      PASSWORD_LENGTH = Admin::Hotels::CreateForm::GENERATED_PASSWORD_LENGTH
      MINIMUM_PASSWORD_LENGTH = 8

      def initialize(account:, params:)
        @account = account
        @params = params
      end

      def call
        password = @params[:password].presence || SecureRandom.alphanumeric(PASSWORD_LENGTH)
        agent = User.new(
          name: @params[:name],
          email: @params[:email],
          role: "super_agent",
          agent_code: ::SuperAgents::GenerateCode.call,
          account: @account,
          password: password,
          password_confirmation: password
        )

        if password.length < MINIMUM_PASSWORD_LENGTH
          agent.validate
          agent.errors.add(:password, "must be at least #{MINIMUM_PASSWORD_LENGTH} characters")
          return Result.new(false, agent, nil)
        end

        agent.save ? Result.new(true, agent, password) : Result.new(false, agent, nil)
      end
    end
  end
end
