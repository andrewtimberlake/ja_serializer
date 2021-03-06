defmodule JaSerializer.Builder.Included do
  @moduledoc false

  alias JaSerializer.Builder.ResourceObject

  defp resource_key(resource) do
    {resource.id, resource.type}
  end

  def build(%{data: data} = context, primary_resources) when is_list(data) do
    known = List.wrap(primary_resources)
    |> Enum.map(&resource_key/1)
    |> Enum.into(HashSet.new)

    do_build(data, context, %{}, known)
    |> Map.values
  end

  def build(context, primary_resources) do
    context
    |> Map.put(:data, [context.data])
    |> build(primary_resources)
  end

  defp do_build([], _context, included, _known_resources), do: included
  defp do_build([struct | structs], context, included, known) do
    context  = Map.put(context, :data, struct)
    included = context
    |> relationships_with_include
    |> Enum.reduce(included, fn item, included ->
      resources_for_relationship(item, context, included, known)
    end)
    do_build(structs, context, included, known)
  end

  defp resource_objects_for(structs, conn, serializer, fields) do
    ResourceObject.build(%{data: structs, conn: conn, serializer: serializer, opts: [fields: fields]})
    |> List.wrap
  end

  # Find relationships that should be included.
  defp relationships_with_include(context) do
    context.serializer.__relations
    |> Enum.filter(fn({_t, rel_name, rel_opts}) ->
      case context[:opts][:include] do
        # if `include` param is not present only return 'default' includes
        nil -> rel_opts[:include] == true

        # otherwise only include requested includes
        includes -> is_list(includes[rel_name])
      end
    end)
  end

  # Find resources for relationship & parent_context
  defp resources_for_relationship({_, name, opts}, context, included, known) do
    context_opts     = context[:opts]
    {cont, included} = apply(context.serializer, name, [context.data, context.conn])
    |> List.wrap
    |> resource_objects_for(context.conn, opts[:serializer], context_opts[:fields])
    |> Enum.reduce({[], included}, fn item, {cont, included} ->
      key = resource_key(item)
      if HashSet.member?(known, key) or Map.has_key?(included, key) do
        {cont, included}
      else
        {[item.data | cont], Map.put(included, key, item)}
      end
    end)

    child_context = context
    |> Map.put(:serializer, opts[:serializer])
    |> Map.put(:opts, opts_with_includes_for_relation(context_opts, name))

    do_build(cont, child_context, included, known)
  end

  defp opts_with_includes_for_relation(opts, rel_name) do
    case opts[:include] do
      nil -> opts
      includes -> Keyword.put(opts, :include, includes[rel_name])
    end
  end
end
