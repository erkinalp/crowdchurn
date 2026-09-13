// @vitest-environment happy-dom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, expect, it, vi } from "vitest";

import { CommunityChatEditor } from "$app/components/ProductEdit/ProductTab/CommunityChatEditor";

afterEach(cleanup);

const settings = {
  community_chat_enabled: true,
  shared_community_id: "shared",
  available_communities: [{ id: "shared", name: "Classroom", product_name: "Writing course" }],
};

it("shows the saved community selection and identifies its source product", () => {
  render(<CommunityChatEditor product={settings} onChange={vi.fn()} />);

  expect(screen.getByRole("combobox", { name: "Community" })).toHaveProperty("value", "shared");
  expect(screen.getByRole("option", { name: "Classroom (from Writing course)" })).toBeTruthy();
});

it("lets a seller switch to a shared community or back to the product's own community", () => {
  const onChange = vi.fn();
  render(<CommunityChatEditor product={{ ...settings, shared_community_id: null }} onChange={onChange} />);
  const selector = screen.getByRole("combobox", { name: "Community" });

  expect(selector).toHaveProperty("value", "");
  fireEvent.change(selector, { target: { value: "shared" } });
  expect(onChange).toHaveBeenLastCalledWith({ shared_community_id: "shared" });

  fireEvent.change(selector, { target: { value: "" } });
  expect(onChange).toHaveBeenLastCalledWith({ shared_community_id: null });
});

it("hides selection while chat is disabled and supports enabling chat", () => {
  const onChange = vi.fn();
  render(<CommunityChatEditor product={{ ...settings, community_chat_enabled: false }} onChange={onChange} />);

  expect(screen.queryByRole("combobox")).toBeNull();
  fireEvent.click(screen.getByRole("switch"));
  expect(onChange).toHaveBeenLastCalledWith({ community_chat_enabled: true });
});

it("supports disabling chat without replacing the selected community in editor state", () => {
  const onChange = vi.fn();
  render(<CommunityChatEditor product={settings} onChange={onChange} />);

  fireEvent.click(screen.getByRole("switch"));
  expect(onChange).toHaveBeenLastCalledWith({ community_chat_enabled: false });
});

it("keeps the first-product flow simple when no shared communities exist", () => {
  render(<CommunityChatEditor product={{ ...settings, available_communities: [] }} onChange={vi.fn()} />);

  expect(screen.queryByRole("combobox")).toBeNull();
  expect(screen.getByRole("switch")).toHaveProperty("checked", true);
});
