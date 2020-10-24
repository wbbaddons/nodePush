/*
 * Copyright (c) 2012 - 2020, Tim Düsterhus
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import { Socket } from "socket.io-client";

class NodePush {
  private initialized = false;
  private connected = false;
  private waitForInit: Promise<typeof Socket>;
  private initResolve!: (value: typeof Socket) => void;
  private initReject!: (reason?: any) => void;

  constructor() {
    this.waitForInit = new Promise((resolve, reject) => {
      this.initResolve = resolve;
      this.initReject = reject;
    });
  }

  /**
   * Connect to the given host and provide the given signed authentication string.
   */
  async init(host: string, connectData: string): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;

    try {
      const socket = (await import("socket.io-client")).default(host);

      let token: string | undefined = undefined;

      socket.on("connect", () => {
        if (token === undefined) {
          socket.emit("connectData", connectData);
        } else {
          socket.emit("token", token);
        }
      });

      socket.on("rekey", (newToken: string) => {
        token = newToken;
      });

      socket.on("authenticated", () => {
        this.connected = true;
      });

      socket.on("disconnect", () => {
        this.connected = false;
      });
      this.initResolve(socket);
    } catch (err) {
      console.log("Initializing nodePush failed:", err);
      this.initReject(err);
    }
  }

  getFeatureFlags(): string[] {
    return [
      "authentication",
      "target:channels",
      "target:groups",
      "target:users",
      "target:registered",
      "target:guest",
    ];
  }

  /**
   * Execute the given callback after connecting to the nodePush service.
   */
  async onConnect(callback: () => unknown): Promise<void> {
    const socket = await this.waitForInit;

    socket.on("authenticated", () => {
      callback();
    });

    if (this.connected) {
      setTimeout(() => {
        callback();
      }, 0);
    }
  }

  /**
   * Execute the given callback after disconnecting from the nodePush service.
   */
  async onDisconnect(callback: () => unknown): Promise<void> {
    const socket = await this.waitForInit;

    socket.on("disconnect", function () {
      callback();
    });
  }

  /**
   * Execute the given callback after receiving the given message from the nodePush service.
   */
  async onMessage(message: string, callback: (payload: unknown) => unknown): Promise<void> {
    if (!/^[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+(\.[a-zA-Z0-9-_]+)+$/.test(message)) {
      throw new Error("Invalid message identifier");
    }

    const socket = await this.waitForInit;

    socket.on(message, (payload: unknown) => {
      callback(payload);
    });
  }
}

export = new NodePush();
