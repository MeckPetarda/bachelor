import { render } from "solid-js/web";
import { Router, Route } from "@solidjs/router";
import App from "./App";

import { Lighthouses } from "./pages/Lighthouses";
import { Groups } from "./pages/Groups";
import { Events } from "./pages/Events";
import { Users } from "./pages/Users";

import "./styles/global.css";

const root = document.getElementById("root");

if (!root) {
  throw new Error("Root element not found");
}

render(
  () => (
    <Router root={App}>
      <Route path="/" component={Lighthouses} />
      <Route path="/groups" component={Groups} />
      <Route path="/events" component={Events} />
      <Route path="/users" component={Users} />
    </Router>
  ),
  root,
);
