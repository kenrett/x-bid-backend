module Account
  class UpdateProfile
    def initialize(user:, name:)
      @user = user
      @name = name
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user
      return ServiceResult.fail("Name can't be blank", code: :validation_error) if @name.to_s.strip.blank?

      if @user.update(name: @name)
        ServiceResult.ok(code: :updated, data: { user: @user })
      else
        ServiceResult.fail(@user.errors.full_messages.to_sentence, code: :validation_error, record: @user)
      end
    end
  end
end
