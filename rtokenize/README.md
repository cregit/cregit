# rtokenize
Ruby tool to tokenise YAML, JSON and other files
- `./rtokenize.rb [-y|--yaml|-j|--json] < file > output_file`

Options:
- `-j|--json` - tokenize JSON file
- `-y|--yaml` - tokenize YAML file
- `-h|--header` - Generate `begin_unit` header and `end_unit` footer
- `-n|--numbers` - Generate numeric stats (first number is Nth call of recursive tokenizer, second number is Nth token within single call)
- `-s N|--split N` - Split string tokens longer than given N
- `-p P|--part-size P` - Split string part size (will split strings longer than N into parts not longer than P), specify P=1 to split every word in strings longer than N

Tool reads from standard input and writes to standard output.
Eventual errors are written to standard error.

# rlocalize
Ruby tool to localize tokens in original file.
When we have tokenized file generated, we may want to know where each token is in the original sorce file.

To check this use:
- `./rlocalize.rb json tokenized_json.token original_json.json [0]`
- `./rlocalize.rb yaml tokenized_yaml.token original_yaml.yaml [0]`

Parameters are: 
- type of file: json or yaml
- tokenized file (output of `./rtokenize.rb`)
- original file
- start position in original file (defaults to 0)

# Shell scripts
Some ready to go Shell scripts:
- `./check_yamls.sh` - this is a check on all Kubernetes YAML files - to see if parser works for all of them.
- `./check_jsons.sh` - this is a check on all Kubernetes JSON files - to see if parser works for all of them.
- `./check_yaml.sh file_name.yaml` - check tokenize & localize on single YAML file
- `./check_json.sh file_name.json` - check tokenize & localize on single JSON file
- `./rtokenize.sh y|j` - read YAML or JSON from stdin, output tokenized & localized to stdout
