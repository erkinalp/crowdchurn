import { Editor } from "@tiptap/core";
import { NodeSelection } from "@tiptap/pm/state";
import * as React from "react";

import { assertDefined } from "$app/utils/assert";

import { buttonVariants } from "$app/components/Button";
import { Icon } from "$app/components/Icons";
import { Popover, PopoverContent, PopoverTrigger } from "$app/components/Popover";

export const NodeActionsMenu = ({
  editor,
  actions,
}: {
  editor: Editor;
  actions?: { item: () => React.ReactNode; menu: (close: () => void) => React.ReactNode }[];
}) => {
  const [open, setOpen] = React.useState(false);
  const selectedNode = editor.state.selection instanceof NodeSelection ? editor.state.selection.node : null;
  const [selectedActionIndex, setSelectedActionIndex] = React.useState<number | null>(null);

  const isOpen = !!selectedNode && open;

  return (
    <Popover open={isOpen} onOpenChange={setOpen} aria-label="Actions">
      <PopoverTrigger>
        <div className={buttonVariants({ color: "filled", size: "sm" })} data-drag-handle draggable>
          <Icon name="outline-drag" />
        </div>
      </PopoverTrigger>
      <PopoverContent className="actions-menu border-0 p-0 shadow-none">
        <div role="menu">
          {actions && selectedActionIndex !== null ? (
            <>
              <div onClick={() => setSelectedActionIndex(null)} role="menuitem">
                <Icon name="outline-cheveron-left" />
                <span>Back</span>
              </div>
              {assertDefined(actions[selectedActionIndex]).menu(() => setOpen(false))}
            </>
          ) : (
            <>
              <div onClick={() => editor.commands.moveNodeUp()} role="menuitem">
                <Icon name="arrow-up" />
                <span>Move up</span>
              </div>
              <div onClick={() => editor.commands.moveNodeDown()} role="menuitem">
                <Icon name="arrow-down" />
                <span>Move down</span>
              </div>
              {actions?.map(({ item }, index) => (
                <div key={index} onClick={() => setSelectedActionIndex(index)} role="menuitem">
                  {item()}
                </div>
              ))}
              <div
                style={{ color: "rgb(var(--danger))" }}
                onClick={() => editor.commands.deleteSelection()}
                role="menuitem"
              >
                <Icon name="trash2" />
                <span>Delete</span>
              </div>
            </>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
};
