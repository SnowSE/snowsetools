defmodule SnowSeTools.Snow.MySnowApi do
  @base_url "https://my.snow.edu/api/"

  def fetch_course_list(term_code: term_code, jwt_token: jwt_token) do
    request_body = %{
      "division_codes" => [],
      "department_codes" => all_department_codes(),
      "subject_codes" => [],
      "instructor_codes" => []
    }

    case Req.post(
           url: "#{@base_url}faculty/sections/#{term_code}",
           headers: [{"cookie", "jwt=#{jwt_token}"}],
           json: request_body
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        normalize_list_response(body, "course list", term_code)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "my.snow.edu returned status #{status} for term #{term_code}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Course list request failed for term #{term_code}: #{format_error(reason)}"}
    end
  end

  def fetch_section_students(term_code: term_code, crn: crn, jwt_token: jwt_token) do
    case Req.get(
           url: "#{@base_url}faculty/section/students?term_code=#{term_code}&crn=#{crn}",
           headers: [{"cookie", "jwt=#{jwt_token}"}]
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        normalize_list_response(body, "student list", "#{term_code}/#{crn}")

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         "my.snow.edu returned status #{status} for term #{term_code} CRN #{crn}: #{inspect(body)}"}

      {:error, reason} ->
        {:error,
         "Roster request failed for term #{term_code} CRN #{crn}: #{format_error(reason)}"}
    end
  end

  defp normalize_list_response(body, _label, _context) when is_list(body), do: {:ok, body}

  defp normalize_list_response(body, label, context) when is_map(body) do
    case Map.values(body) do
      [list] when is_list(list) -> {:ok, list}
      _ -> {:error, "my.snow.edu returned unexpected #{label} payload for #{context}"}
    end
  end

  defp normalize_list_response(_body, label, context) do
    {:error, "my.snow.edu returned unexpected #{label} payload for #{context}"}
  end

  defp all_department_codes do
    [
      "AD",
      "BSCI",
      "BIOL",
      "BUS",
      "CHEM",
      "COMM",
      "ENCS",
      "CM",
      "CED",
      "DANC",
      "EDFS",
      "ENPH",
      "EXSC",
      "GEOL",
      "AHNA",
      "HONR",
      "INDM",
      "ITEC",
      "LALI",
      "MATH",
      "MUSC",
      "NR",
      "NURS",
      "PHSX",
      "STEC",
      "SS",
      "THEA",
      "TRAN",
      "ART"
    ]
  end

  defp format_error(%{message: message}) when is_binary(message), do: message
  defp format_error(reason), do: inspect(reason)
end
