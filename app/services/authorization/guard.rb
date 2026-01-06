module Authorization
  class Guard
    ROLE_LABELS = {
      user: "User",
      admin: "Admin",
      superadmin: "Superadmin"
    }.freeze

    def self.allow?(actor:, role:)
      return false unless actor

      case role.to_sym
      when :user
        true
      when :admin
        actor.admin? || actor.superadmin?
      when :superadmin
        actor.superadmin?
      else
        raise ArgumentError, "Unknown role: #{role.inspect}"
      end
    end

    def self.default_forbidden_message(role)
      label = ROLE_LABELS.fetch(role.to_sym) { role.to_s }
      "#{label} privileges required"
    end

    def self.owner?(actor:, owner_id:)
      return false unless actor
      return false if owner_id.blank?

      actor.id.to_s == owner_id.to_s
    end
  end
end
