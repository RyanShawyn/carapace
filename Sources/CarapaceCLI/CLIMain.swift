import Foundation
import CarapaceCore

@main
struct CarapaceCLI {
    static func main() async {
        do {
            let args = try CLIArgs(Array(CommandLine.arguments.dropFirst()))
            if args.switches.contains("help") || args.group.isEmpty {
                printHelp()
                return
            }
            if args.group == "version" {
                Output.success(version(), args: args, store: nil)
                return
            }
            if args.group == "schema" {
                Output.success(schema(), args: args, store: nil)
                return
            }
            let store = try Store(path: args.dbPath ?? Store.defaultPath)
            let data = try await Router.run(args: args, store: store)
            Output.success(data, args: args, store: store)
        } catch let error as CLIError {
            Output.failure(error)
            exit(error.exitCode)
        } catch let error as StoreError {
            let mapped = mapStoreError(error)
            Output.failure(mapped)
            exit(mapped.exitCode)
        } catch {
            let mapped = CLIError(code: "INTERNAL", message: error.localizedDescription, hint: nil, exitCode: 9)
            Output.failure(mapped)
            exit(9)
        }
    }

    private static func printHelp() {
        let help = """
        carapace <group> <verb> [flags]

        分组：
          doctor                         环境自检
          schema                         输出命令与版本
          version                        版本
          portfolio                      组合总览
          positions list|get|add|correct|clear|changes
          trades   record|list
          plans    get|update|remove
          drafts   list|create|apply|discard
          watch    list|add|update|remove|convert|carry
          import   preview|commit|rollback|batches|executions
          accounts list|add
          reviews  list|get|create|save
          memories list|context|add|update|archive
          metrics  list|set
          style    compute|snapshots|save
          alerts   list|ack|ack-all
          notifications list|read|read-all
          quotes   get|tracked|indices
          search   --keyword TEXT
          settings list|get|set
          backup   --to PATH
          verify
          export-csv --to PATH
          maintenance purge-ai-keys

        通用参数：
          --json (默认)  --format text  --db PATH
          --dry-run  --yes  --request-id ID  --no-notify
          --mapping-file PATH  --include-needs-review（import）
        """
        print(help)
    }
}