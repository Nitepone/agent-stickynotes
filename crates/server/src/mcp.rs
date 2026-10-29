//! MCP transport: tools and resources over Streamable HTTP at `/mcp`.

use rmcp::handler::server::router::tool::ToolRouter;
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::{
    Implementation, ListResourcesResult, PaginatedRequestParams, ReadResourceRequestParams,
    ReadResourceResponse, ReadResourceResult, Resource, ResourceContents, ServerCapabilities,
    ServerConfig,
};
use rmcp::service::RequestContext;
use rmcp::{ErrorData, RoleServer, ServerHandler, schemars, tool, tool_handler, tool_router};
use serde::{Deserialize, Serialize};
use stickynotes_core::agent_guide;

use crate::service::{
    AgentService, CriterionInput, NewTask, ReferenceInput, ServiceResult, TaskUpdate,
};

const BOARD_URI: &str = "stickynotes://board";
const BOARD_MD_URI: &str = "stickynotes://board.md";

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct TaskListArgs {
    /// Only list tasks in this column (id or exact title).
    pub column: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct TaskIdArgs {
    /// Task id.
    pub id: String,
    /// Fail if the board revision differs (optional).
    pub expected_revision: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct TaskCreateArgs {
    /// Short, sticky-note sized summary (about 200 characters suggested). Required.
    pub description: String,
    /// Longer free-form details.
    #[serde(default)]
    pub extended_description: String,
    #[serde(default)]
    pub requirements: Vec<String>,
    /// Acceptance criteria texts; they start unchecked.
    #[serde(default)]
    pub acceptance_criteria: Vec<String>,
    pub expected_revision: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct CriterionArg {
    /// Id of an existing criterion to keep (omit to add a new one).
    pub id: Option<String>,
    pub text: String,
    #[serde(default)]
    pub done: bool,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct TaskUpdateArgs {
    pub id: String,
    /// New short description (about 200 characters suggested).
    pub description: Option<String>,
    pub extended_description: Option<String>,
    /// Replaces the whole requirements list.
    pub requirements: Option<Vec<String>>,
    /// Replaces the whole criteria list. Pass existing ids to keep criteria.
    pub acceptance_criteria: Option<Vec<CriterionArg>>,
    /// Replaces all links to other tasks (pass the existing ones to keep
    /// them; omit the field to leave links alone). The other task gets the
    /// mirrored relation automatically.
    pub references: Option<Vec<ReferenceArg>>,
    pub expected_revision: Option<u64>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct ReferenceArg {
    /// Id of the other task.
    pub task_id: String,
    /// What this task does to the other: blocks, blocked_by, relates_to,
    /// duplicates or duplicated_by.
    pub relation: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct CriterionSetArgs {
    pub task_id: String,
    pub criterion_id: String,
    pub done: bool,
    pub expected_revision: Option<u64>,
}

#[derive(Clone)]
pub struct BoardMcp {
    service: AgentService,
    tool_router: ToolRouter<Self>,
}

impl BoardMcp {
    pub fn new(service: AgentService) -> Self {
        BoardMcp {
            service,
            tool_router: Self::tool_router(),
        }
    }
}

type ToolResult = Result<String, String>;

fn json<T: Serialize>(result: ServiceResult<T>) -> ToolResult {
    result
        .map(|v| serde_json::to_string_pretty(&v).expect("views serialize"))
        .map_err(|e| e.to_string())
}

#[tool_router]
impl BoardMcp {
    #[tool(
        description = "Get the project's instructions from the user: document_prompt (how to write documents) and code_guidance (how to write code). Call this first and follow it."
    )]
    fn project_get(&self) -> ToolResult {
        json(Ok(self.service.project()))
    }

    #[tool(
        description = "Get the whole board: ordered columns (with their entry-criteria descriptions), task summaries, the current revision, and whether agent write access is enabled."
    )]
    fn board_get(&self) -> ToolResult {
        json(Ok(self.service.board()))
    }

    #[tool(description = "List task summaries, optionally only those in one column.")]
    fn task_list(&self, Parameters(a): Parameters<TaskListArgs>) -> ToolResult {
        json(self.service.list_tasks(a.column.as_deref()))
    }

    #[tool(
        description = "Get a task with all fields, its current column, and next_column (the column task_advance would move it to, including that column's entry criteria)."
    )]
    fn task_get(&self, Parameters(a): Parameters<TaskIdArgs>) -> ToolResult {
        json(self.service.task(&a.id))
    }

    #[tool(
        description = "Create a task in the first column. Keep description short (~200 chars); put detail in extended_description, requirements and acceptance_criteria."
    )]
    fn task_create(&self, Parameters(a): Parameters<TaskCreateArgs>) -> ToolResult {
        let new = NewTask {
            description: a.description,
            extended_description: a.extended_description,
            requirements: a.requirements,
            acceptance_criteria: a.acceptance_criteria,
        };
        json(self.service.create_task(new, a.expected_revision))
    }

    #[tool(
        description = "Update a task. Omitted fields are unchanged; lists (requirements, acceptance_criteria, references) replace the existing list. Keep description short (~200 chars). To link tasks, pass references like [{\"task_id\": \"...\", \"relation\": \"blocks\"}]; the other task is updated to match."
    )]
    fn task_update(&self, Parameters(a): Parameters<TaskUpdateArgs>) -> ToolResult {
        let criteria = match a.acceptance_criteria {
            None => None,
            Some(cs) => Some(
                cs.into_iter()
                    .map(|c| {
                        let id =
                            c.id.map(|id| {
                                id.parse()
                                    .map_err(|_| format!("'{id}' is not a valid criterion id"))
                            })
                            .transpose()?;
                        Ok(CriterionInput {
                            id,
                            text: c.text,
                            done: c.done,
                        })
                    })
                    .collect::<Result<Vec<_>, String>>()?,
            ),
        };
        let update = TaskUpdate {
            description: a.description,
            extended_description: a.extended_description,
            requirements: a.requirements,
            acceptance_criteria: criteria,
            references: a.references.map(|refs| {
                refs.into_iter()
                    .map(|r| ReferenceInput {
                        task_id: r.task_id,
                        relation: r.relation,
                    })
                    .collect()
            }),
        };
        json(self.service.update_task(&a.id, update, a.expected_revision))
    }

    #[tool(
        description = "Move a task one column to the right. First call task_get and confirm the task meets next_column.description; only advance when it does."
    )]
    fn task_advance(&self, Parameters(a): Parameters<TaskIdArgs>) -> ToolResult {
        json(self.service.advance_task(&a.id, a.expected_revision))
    }

    #[tool(description = "Delete a task permanently.")]
    fn task_delete(&self, Parameters(a): Parameters<TaskIdArgs>) -> ToolResult {
        json(self.service.delete_task(&a.id, a.expected_revision))
    }

    #[tool(description = "Mark an acceptance criterion as done or not done.")]
    fn criterion_set(&self, Parameters(a): Parameters<CriterionSetArgs>) -> ToolResult {
        json(
            self.service
                .set_criterion(&a.task_id, &a.criterion_id, a.done, a.expected_revision),
        )
    }
}

#[tool_handler(router = self.tool_router)]
impl ServerHandler for BoardMcp {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(
            ServerCapabilities::builder()
                .enable_tools()
                .enable_resources()
                .build(),
        )
        .with_server_info(Implementation::new(
            "stickynotes",
            env!("CARGO_PKG_VERSION"),
        ))
        .with_instructions(agent_guide::mcp_instructions())
    }

    async fn list_resources(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListResourcesResult, ErrorData> {
        Ok(ListResourcesResult::with_all_items(vec![
            Resource::new(BOARD_URI, "board")
                .with_description("The current board as JSON")
                .with_mime_type("application/json"),
            Resource::new(BOARD_MD_URI, "board.md")
                .with_description("The current board as Markdown")
                .with_mime_type("text/markdown"),
        ]))
    }

    async fn read_resource(
        &self,
        request: ReadResourceRequestParams,
        _context: RequestContext<RoleServer>,
    ) -> Result<ReadResourceResponse, ErrorData> {
        let (text, mime) = match request.uri.as_str() {
            BOARD_URI => (
                serde_json::to_string_pretty(&self.service.board()).expect("serializes"),
                "application/json",
            ),
            BOARD_MD_URI => (self.service.markdown(), "text/markdown"),
            other => {
                return Err(ErrorData::resource_not_found(
                    format!("unknown resource {other}"),
                    None,
                ));
            }
        };
        Ok(ReadResourceResult::new(vec![
            ResourceContents::text(text, request.uri).with_mime_type(mime),
        ])
        .into())
    }
}
