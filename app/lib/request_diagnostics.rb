module RequestDiagnostics
  module_function

  def redact_token(token, head: 6, tail: 6)
    return nil if token.blank?

    token = token.to_s
    return "[redacted]" if token.length <= (head + tail)

    "#{token[0, head]}...#{token[-tail, tail]}"
  end

  def redact_authorization_header(header)
    return nil if header.blank?

    redact_token(header.to_s.split(" ").last)
  end

  def cookie_names_from_header(header)
    return [] if header.blank?

    header.split(";").map { |pair| pair.split("=", 2).first.to_s.strip }.reject(&:blank?).uniq
  end

  def normalize_origin(origin)
    origin.to_s.strip.delete_suffix("/")
  end
end
