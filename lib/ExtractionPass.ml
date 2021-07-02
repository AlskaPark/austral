open Identifier
open Imports
open Type
open Combined
open Semantic
open ModuleSystem
open TypeParser

let rec extract_type_signatures (CombinedModule { decls; _ }) =
  List.filter_map extract_type_signatures' decls

and extract_type_signatures' (def: combined_definition) =
  match def with
  | CConstant _ ->
     None
  | CTypeAlias (_, name, typarams, universe, _, _) ->
     Some (TypeSignature (name, typarams, universe))
  | CRecord (_, name, typarams, universe, _, _) ->
     Some (TypeSignature (name, typarams, universe))
  | CUnion (_, name, typarams, universe, _, _) ->
     Some (TypeSignature (name, typarams, universe))
  | CFunction _ ->
     None
  | CTypeclass _ ->
     None
  | CInstance _ ->
     None

let rec extract_declarations (module_name: module_name) (menv: menv) local_types (CombinedModule { decls; _ }) =
  List.map (extract_declaration module_name menv local_types) decls

and extract_declaration (module_name: module_name) (menv: menv) (local_types: type_signature list) (def: combined_definition) =
  let parse' = parse_type menv local_types in
  let rec parse_slot (typarams: type_parameter list) (QualifiedSlot (n, ts)): typed_slot =
    TypedSlot (n, parse' typarams ts)
  and parse_case (typarams: type_parameter list) (QualifiedCase (n, ss)): typed_case =
    TypedCase (n, List.map (parse_slot typarams) ss)
  and parse_param (typarams: type_parameter list) (QualifiedParameter (n, ts)): value_parameter =
    ValueParameter (n, parse' typarams ts)
  and parse_method_decl (typarams: type_parameter list) (CMethodDecl (name, params, rt, _)): semantic_method_decl =
    SMethodDecl (name, List.map (parse_param typarams) params, parse' typarams rt)
  and parse_method_def (typarams: type_parameter list) (CMethodDef (name, params, rt, _, _)): semantic_method_decl =
    SMethodDecl (name, List.map (parse_param typarams) params, parse' typarams rt)
  in
  match def with
  | CConstant (vis, name, typespec, _, _) ->
     SConstantDefinition (vis, name, parse' [] typespec)
  | CTypeAlias (vis, name, typarams, universe, typespec, _) ->
     STypeAliasDefinition (vis, name, typarams, universe, parse' typarams typespec)
  | CRecord (vis, name, typarams, universe, slots, _) ->
     SRecordDefinition (module_name, vis, name, typarams, universe, List.map (parse_slot typarams) slots)
  | CUnion (vis, name, typarams, universe, cases, _) ->
     SUnionDefinition (module_name, vis, name, typarams, universe, List.map (parse_case typarams) cases)
  | CFunction (vis, name, typarams, params, rt, _, _, _) ->
     SFunctionDeclaration (vis, name, typarams, List.map (parse_param typarams) params, parse' typarams rt)
  | CTypeclass (vis, name, typaram, methods, _) ->
     STypeClassDecl (STypeClass (vis, name, typaram, List.map (parse_method_decl [typaram]) methods))
  | CInstance (vis, name, typarams, argument, methods, _) ->
     STypeClassInstanceDecl (STypeClassInstance (vis, name, typarams, parse' typarams argument, List.map (parse_method_def typarams) methods))

let append_if_not_present (list: 'a list) (elem: 'a) (key: 'a -> 'b) =
  if List.exists (fun el -> (key el) = (key elem)) list then
    list
  else
    List.cons elem list

let rec merge_without_duplicates (a: 'a list) (b: 'a list) (key: 'a -> 'b) =
  match b with
  | first::rest -> merge_without_duplicates (append_if_not_present a first key) rest key
  | [] -> a

let extract menv cmodule =
  let (CombinedModule { name; interface_imports; body_imports; _ }) = cmodule in
  let sigs = extract_type_signatures cmodule in
  let sem_decls = extract_declarations name menv sigs cmodule in
  let (classes': semantic_typeclass list) = merge_without_duplicates (imported_classes interface_imports)
                   (imported_classes body_imports)
                   (fun (STypeClass (_, n, _, _)) -> n) in
  let (instances': semantic_instance list) = merge_without_duplicates (imported_instances interface_imports)
                   (imported_instances body_imports)
                   (fun (STypeClassInstance (_, n, _, _, _)) -> n) in
  SemanticModule {
      name=name;
      decls=sem_decls;
      imported_classes=classes';
      imported_instances=instances'
    }
