%{
  configs: [
    %{
      name: "default",
      checks: %{
        enabled: [
          # Require @spec on the domain layer (contexts, schemas, pure logic),
          # where types are worth checking. The web layer (HEEx components,
          # controller actions, the newton_web.ex macros) is excluded — specs
          # there are ceremonial noise.
          {Credo.Check.Readability.Specs, files: %{included: ["lib/newton/"]}}
        ],
        disabled: [
          {Credo.Check.Readability.ModuleDoc, []}
        ]
      }
    }
  ]
}
