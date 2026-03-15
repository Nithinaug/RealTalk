let client;
let configError;

try {
  const { SUPABASE_URL, SUPABASE_ANON_KEY } = CONFIG;
  client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
} catch {
  configError = "Supabase configuration is missing.";
}

let socket;
let myName = "";
let joined = false;

function isMe(username) {
  if (!username || !myName) return false;
  return username.trim().toLowerCase() === myName.trim().toLowerCase();
}

document.addEventListener("DOMContentLoaded", () => {
  const authWrapper       = document.getElementById("auth-container");
  const loginForm         = document.getElementById("login-form");
  const signupForm        = document.getElementById("signup-form");
  const showSignup        = document.getElementById("show-signup");
  const showLogin         = document.getElementById("show-login");
  const loginBtn          = document.getElementById("login-button");
  const signupBtn         = document.getElementById("signup-button");
  const clearChatBtn      = document.getElementById("clear-chat-button");
  const logoutBtn         = document.getElementById("logout-button");
  const mainChat          = document.getElementById("main-chat");
  const msgBox            = document.getElementById("chatInput");
  const msgArea           = document.getElementById("chatMessages");
  const usersBox          = document.getElementById("onlineUsers");
  const roomsBox          = document.getElementById("userRoomsList");
  const displayName       = document.getElementById("display-name");
  const sendBtn           = document.getElementById("send-btn");
  const onlineCount       = document.getElementById("online-count");
  const createRoomBtn     = document.getElementById("show-create-room");
  const joinRoomBtn       = document.getElementById("show-join-room");
  const createRoomSubmit  = document.getElementById("create-room-submit");
  const joinRoomSubmit    = document.getElementById("join-room-submit");
  const backToRoomsNav    = document.getElementById("back-to-rooms-nav");
  const roomSelector      = document.getElementById("room-selection-container");
  const roomsListView     = document.getElementById("rooms-list-view");
  const createRoomView    = document.getElementById("create-room-view");
  const joinRoomView      = document.getElementById("join-room-view");
  const joinedRoomsList   = document.getElementById("joined-rooms-list");
  const currentRoomLabel  = document.getElementById("current-room-name");
  const sidebarAddRoomBtn = document.getElementById("sidebar-add-room-btn");
  const authBackBtn       = document.getElementById("auth-back-to-login");
  const createRoomNameInput = document.getElementById("create-room-name");
  const createRoomIdInput   = document.getElementById("create-room-id");
  const joinRoomIdInput     = document.getElementById("join-room-id");

  let currentRoom = null;
  let realtimeChannel = null;

  authBackBtn.onclick = () => {
    roomSelector.style.display = "none";
    authWrapper.style.display = "flex";
    showLogin.click();
  };

  function showRoomList() {
    roomsListView.style.display = "flex";
    createRoomView.style.display = "none";
    joinRoomView.style.display = "none";
    createRoomNameInput.value = "";
    createRoomIdInput.value = "";
    joinRoomIdInput.value = "";
    renderJoinedRooms();
  }

  createRoomBtn.onclick = () => {
    roomsListView.style.display = "none";
    createRoomView.style.display = "block";
  };

  joinRoomBtn.onclick = () => {
    roomsListView.style.display = "none";
    joinRoomView.style.display = "block";
  };

  document.querySelectorAll(".back-to-rooms").forEach(btn => {
    btn.onclick = showRoomList;
  });

  backToRoomsNav.onclick = () => {
    mainChat.style.display = "none";
    roomSelector.style.display = "flex";

    if (socket && socket.readyState === 1) {
      socket.send(JSON.stringify({ type: "leave", user: myName, room: currentRoom?.id ?? "" }));
    }
    if (realtimeChannel) {
      realtimeChannel.unsubscribe();
      realtimeChannel = null;
    }

    currentRoom = null;
    joined = false;
    msgArea.innerHTML = "";
    onlineCount.textContent = "0 online";
    usersBox.innerHTML = "";
    showRoomList();
  };

  sidebarAddRoomBtn.onclick = () => {
    mainChat.style.display = "none";
    roomSelector.style.display = "flex";
    showRoomList();
  };

  async function getJoinedRooms() {
    const { data: { user } } = await client.auth.getUser();
    const { data, error } = await client
      .from("user_rooms")
      .select("rooms(id, name, creator_id)")
      .eq("user_id", user.id);
    if (error) return [];
    return data.map(item => item.rooms);
  }

  async function saveJoinedRoom(id, name) {
    const { data: { user } } = await client.auth.getUser();
    const { data: existing } = await client.from("rooms").select("id").eq("id", id).single();
    if (!existing) {
      await client.from("rooms").insert({ id, name, creator_id: user.id });
    }
    await client.from("user_rooms").upsert({ user_id: user.id, room_id: id });
  }

  async function renderJoinedRooms() {
    const rooms = await getJoinedRooms();
    const { data: { user } } = await client.auth.getUser();
    const activeId = currentRoom?.id ?? null;

    joinedRoomsList.innerHTML = "";
    joinedRoomsList.style.display = rooms.length === 0 ? "none" : "grid";

    rooms.forEach(room => {
      const card = document.createElement("div");
      card.className = "room-card";
      if (room.id === activeId) card.classList.add("active");
      card.onclick = () => joinRoom(room.id, room.name);

      const icon = document.createElement("div");
      icon.innerHTML = `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--primary)" stroke-width="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M23 21v-2a4 4 0 0 0-3-3.87"></path><path d="M16 3.13a4 4 0 0 1 0 7.75"></path></svg>`;

      const nameSpan = document.createElement("span");
      nameSpan.textContent = room.name;

      const actions = document.createElement("div");
      actions.className = "card-actions";

      if (room.creator_id === user.id) {
        const delBtn = document.createElement("button");
        delBtn.className = "btn-card-action delete";
        delBtn.title = "Delete Room";
        delBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 6h18m-2 0v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6m3 0V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2m-6 5v6m4-6v6"/></svg>`;
        delBtn.onclick = e => { e.stopPropagation(); deleteRoom(room.id); };
        actions.appendChild(delBtn);
      } else {
        const exitBtn = document.createElement("button");
        exitBtn.className = "btn-card-action exit";
        exitBtn.title = "Exit Room";
        exitBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4m7 14l5-5-5-5m5 5H9"/></svg>`;
        exitBtn.onclick = e => { e.stopPropagation(); exitRoom(room.id); };
        actions.appendChild(exitBtn);
      }

      card.appendChild(icon);
      card.appendChild(nameSpan);
      card.appendChild(actions);
      joinedRoomsList.appendChild(card);
    });

    roomsBox.innerHTML = "";
    rooms.forEach(room => {
      const item = document.createElement("div");
      item.className = "room-item";
      if (room.id === activeId) item.classList.add("active");
      item.onclick = () => { if (activeId !== room.id) joinRoom(room.id, room.name); };
      item.innerHTML = `<span class="room-name">${room.name}</span>`;
      roomsBox.appendChild(item);
    });
  }

  async function deleteRoom(id) {
    if (!confirm("Delete this room for everyone?")) return;
    const { error } = await client.from("rooms").delete().eq("id", id);
    if (error) return alert("Could not delete the room.");
    if (currentRoom?.id === id) backToRoomsNav.click();
    renderJoinedRooms();
  }

  async function exitRoom(id) {
    if (!confirm("Remove this room from your list?")) return;
    const { data: { user } } = await client.auth.getUser();
    const { error } = await client.from("user_rooms").delete().eq("user_id", user.id).eq("room_id", id);
    if (error) return alert("Could not exit room.");
    if (currentRoom?.id === id) backToRoomsNav.click();
    renderJoinedRooms();
  }

  async function joinRoom(id, name) {
    if (!id || !name) return;
    if (!/^[a-zA-Z0-9]+$/.test(id)) return alert("Room ID can only contain letters and numbers.");

    currentRoom = { id, name };
    await saveJoinedRoom(id, name);

    currentRoomLabel.textContent = `Room: ${name}`;
    roomSelector.style.display = "none";
    mainChat.style.display = "flex";
    joined = true;

    await renderJoinedRooms();
    await fetchHistory();
    connectWebSocket();
    setupRealtime();
  }

  async function handleCreateRoom() {
    const id   = createRoomIdInput.value.trim();
    const name = createRoomNameInput.value.trim();
    if (!id || !name) return alert("Please enter both a Room Name and Room ID.");

    const { data: existing } = await client.from("rooms").select("id").eq("id", id).maybeSingle();
    if (existing) return alert("A room with this ID already exists.");

    joinRoom(id, name);
  }

  async function handleJoinRoom() {
    const id = joinRoomIdInput.value.trim();
    if (!id) return alert("Please enter the Room ID.");

    const { data: existing } = await client.from("rooms").select("id, name").eq("id", id).maybeSingle();
    if (!existing) return alert("Room not found. Check the ID or create a new room.");

    joinRoom(id, existing.name);
  }

  createRoomSubmit.onclick = handleCreateRoom;
  joinRoomSubmit.onclick   = handleJoinRoom;
  createRoomIdInput.addEventListener("keydown", e => { if (e.key === "Enter") createRoomSubmit.click(); });
  joinRoomIdInput.addEventListener("keydown",   e => { if (e.key === "Enter") joinRoomSubmit.click(); });

  showSignup.onclick = e => { e.preventDefault(); loginForm.style.display = "none"; signupForm.style.display = "block"; };
  showLogin.onclick  = e => { e.preventDefault(); signupForm.style.display = "none"; loginForm.style.display = "block"; };

  function setBtnLoading(btn, loading) {
    const text   = btn.querySelector(".btn-text") || btn;
    const loader = btn.querySelector(".loader");
    if (loader) {
      text.style.display   = loading ? "none"  : "block";
      loader.style.display = loading ? "block" : "none";
    }
    btn.disabled = loading;
  }

  async function handleLogin() {
    const username = document.getElementById("login-username").value.trim();
    const password = document.getElementById("login-password").value;
    if (!username || !password) return alert("Please enter your username and password.");
    if (!client) return alert("App configuration is missing.");

    setBtnLoading(loginBtn, true);
    const { data, error } = await client.auth.signInWithPassword({
      email: `${username}@example.com`,
      password
    });
    setBtnLoading(loginBtn, false);

    if (error) return alert(error.message);
    onAuthenticated(data.user);
  }

  async function handleSignup() {
    const username = document.getElementById("signup-username").value.trim();
    const password = document.getElementById("signup-password").value;
    if (!username || !password) return alert("Please enter a username and password.");
    if (password.length < 6) return alert("Password must be at least 6 characters.");
    if (!client) return alert("App configuration is missing.");

    setBtnLoading(signupBtn, true);
    const { error } = await client.auth.signUp({
      email: `${username}@example.com`,
      password,
      options: { data: { username } }
    });
    setBtnLoading(signupBtn, false);

    if (error) return alert(error.message);
    alert("Account created! You can now log in.");
    showLogin.click();
  }

  async function handleLogout() {
    if (confirm("Log out?")) {
      await client.auth.signOut();
      location.reload();
    }
  }

  async function handleClearChat() {
    if (!currentRoom) return;
    if (!confirm("Clear your chat history for this room?")) return;

    const { data: { user } } = await client.auth.getUser();
    const { error } = await client.from("user_room_clears").upsert({
      user_id: user.id,
      room_id: currentRoom.id,
      cleared_at: new Date().toISOString()
    });

    if (error) return alert("Failed to clear chat history.");
    msgArea.innerHTML = "";
  }

  loginBtn.onclick    = handleLogin;
  signupBtn.onclick   = handleSignup;
  clearChatBtn.onclick = handleClearChat;
  logoutBtn.onclick   = handleLogout;

  document.getElementById("login-username").addEventListener("keydown", e => { if (e.key === "Enter") handleLogin(); });
  document.getElementById("login-password").addEventListener("keydown", e => { if (e.key === "Enter") handleLogin(); });

  function onAuthenticated(user) {
    myName = (user.user_metadata?.username || user.email.split("@")[0]).trim();
    displayName.textContent = myName;
    authWrapper.style.display = "none";
    roomSelector.style.display = "flex";
    showRoomList();
    renderJoinedRooms();
  }

  async function fetchHistory() {
    if (!currentRoom) return;

    const { data: { user } } = await client.auth.getUser();

    const { data: clearRecord } = await client
      .from("user_room_clears")
      .select("cleared_at")
      .eq("user_id", user.id)
      .eq("room_id", currentRoom.id)
      .maybeSingle();

    const clearedAt = clearRecord?.cleared_at ?? "1970-01-01T00:00:00Z";

    const { data: deletedRecords } = await client
      .from("user_deleted_messages")
      .select("message_id")
      .eq("user_id", user.id);

    const deletedIds = (deletedRecords ?? []).map(r => r.message_id);

    const { data: messages, error } = await client
      .from("messages")
      .select("*")
      .eq("room_id", currentRoom.id)
      .gt("created_at", clearedAt)
      .order("created_at", { ascending: true })
      .limit(100);

    if (error) throw error;

    msgArea.innerHTML = "";
    const fragment = document.createDocumentFragment();
    messages.forEach(msg => {
      if (!deletedIds.includes(msg.id)) {
        fragment.appendChild(createMsgElement(msg.username, msg.text, msg.created_at, msg.id));
      }
    });
    msgArea.appendChild(fragment);
    msgArea.scrollTop = msgArea.scrollHeight;
  }

  function setupRealtime() {
    if (realtimeChannel) realtimeChannel.unsubscribe();

    realtimeChannel = client.channel(`room:${currentRoom.id}`)
      .on("postgres_changes", {
        event: "INSERT", schema: "public", table: "messages",
        filter: `room_id=eq.${currentRoom.id}`
      }, payload => {
        if (!isMe(payload.new.username)) {
          addMsg(payload.new.username, payload.new.text, payload.new.created_at, payload.new.id);
        }
      })
      .on("postgres_changes", {
        event: "DELETE", schema: "public", table: "messages"
      }, payload => {
        document.querySelector(`[data-id="${payload.old.id}"]`)?.remove();
      })
      .on("postgres_changes", {
        event: "INSERT", schema: "public", table: "user_deleted_messages"
      }, payload => {
        client.auth.getUser().then(({ data }) => {
          if (data?.user && payload.new.user_id === data.user.id) {
            document.querySelector(`[data-id="${payload.new.message_id}"]`)?.remove();
          }
        });
      })
      .on("postgres_changes", {
        event: "UPSERT", schema: "public", table: "user_room_clears"
      }, payload => {
        if (payload.new.room_id === currentRoom.id) msgArea.innerHTML = "";
      })
      .subscribe();
  }

  async function connectWebSocket() {
    if (socket && socket.readyState !== WebSocket.CLOSED) socket.close();

    const { data: { session } } = await client.auth.getSession();
    const token = session?.access_token || "";

    const proto = location.protocol === "https:" ? "wss" : "ws";
    socket = new WebSocket(`${proto}://${location.host}/ws`, token ? [token] : undefined);

    socket.onopen = () => {
      if (myName && joined && currentRoom) {
        socket.send(JSON.stringify({ type: "join", user: myName, room: currentRoom.id }));
      }
    };

    socket.onmessage = e => {
      const msg = JSON.parse(e.data);
      if (msg.room && msg.room !== currentRoom.id) return;

      if (msg.type === "users") {
        showUsers(msg.users);
        onlineCount.textContent = `${msg.users.length} online`;
      } else if (msg.type === "message" && msg.user !== myName) {
        addMsg(msg.user, msg.text, new Date().toISOString(), msg.id);
      }
    };

    socket.onclose = () => {
      if (joined && currentRoom) setTimeout(connectWebSocket, 3000);
    };
  }

  async function sendMessage() {
    const text = msgBox.value.trim();
    if (!text || !joined || !currentRoom) return;

    const { data: authData } = await client.auth.getUser();
    const { data, error } = await client.from("messages").insert({
      username: myName,
      user_id: authData?.user?.id,
      text,
      room_id: currentRoom.id
    }).select().single();

    if (error) return alert("Failed to send message.");

    addMsg(myName, text, new Date().toISOString(), data.id);
    msgBox.value = "";

    if (socket && socket.readyState === 1) {
      socket.send(JSON.stringify({ type: "message", user: myName, text, room: currentRoom.id }));
    }
  }

  sendBtn.onclick  = sendMessage;
  msgBox.onkeydown = e => { if (e.key === "Enter") sendMessage(); };

  const trashSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>`;

  function createMsgElement(user, text, timestamp, id) {
    const bubble = document.createElement("div");
    bubble.className = isMe(user) ? "msg me" : "msg other";
    if (id) bubble.setAttribute("data-id", id);

    const nameSpan = document.createElement("span");
    nameSpan.className = "name";
    nameSpan.textContent = isMe(user) ? "You" : (user || "Unknown");

    const contentSpan = document.createElement("span");
    contentSpan.className = "msg-content";
    contentSpan.textContent = text;

    const timeSpan = document.createElement("span");
    timeSpan.className = "time";
    if (timestamp) {
      timeSpan.textContent = new Date(timestamp).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    }

    const actions = document.createElement("div");
    actions.className = "msg-actions";

    const delMeBtn = document.createElement("button");
    delMeBtn.className = "btn-delete me-only";
    delMeBtn.title = "Delete for Me";
    delMeBtn.innerHTML = `${trashSvg}<span class="label">For Me</span>`;
    delMeBtn.onclick = () => deleteMessageForMe(id, bubble);
    actions.appendChild(delMeBtn);

    if (isMe(user)) {
      const delAllBtn = document.createElement("button");
      delAllBtn.className = "btn-delete all";
      delAllBtn.title = "Delete for Everyone";
      delAllBtn.innerHTML = `${trashSvg}<span class="label">For All</span>`;
      delAllBtn.onclick = () => deleteMessageForEveryone(id);
      actions.appendChild(delAllBtn);
    }

    bubble.appendChild(nameSpan);
    bubble.appendChild(contentSpan);
    bubble.appendChild(timeSpan);
    bubble.appendChild(actions);

    return bubble;
  }

  async function deleteMessageForEveryone(msgId) {
    if (!msgId) return alert("Message ID not found. Please refresh and try again.");
    if (!confirm("Delete this message for everyone?")) return;

    const { error } = await client.from("messages").delete().eq("id", msgId);
    if (error) alert("Could not delete: " + error.message);
  }

  async function deleteMessageForMe(msgId, element) {
    if (!msgId) return;
    const { data: { user } } = await client.auth.getUser();
    const { error } = await client.from("user_deleted_messages")
      .insert({ user_id: user.id, message_id: msgId });
    if (error) return alert("Could not delete message.");
    element.remove();
  }

  const recentMessages = [];

  function addMsg(user, text, timestamp, id) {
    const now = Date.now();
    while (recentMessages.length > 0 && now - recentMessages[0].time > 2500) {
      recentMessages.shift();
    }
    const sig = `${user}:${text}`;
    if (recentMessages.some(m => m.sig === sig)) return;
    recentMessages.push({ sig, time: now });

    const bubble = createMsgElement(user, text, timestamp, id);
    msgArea.appendChild(bubble);
    msgArea.scrollTop = msgArea.scrollHeight;
  }

  function showUsers(users) {
    usersBox.innerHTML = "";
    const fragment = document.createDocumentFragment();
    users.forEach(name => {
      const item = document.createElement("div");
      item.className = "user-item";
      item.innerHTML = `<div class="user-avatar">${name.charAt(0).toUpperCase()}</div><span>${name}</span>`;
      fragment.appendChild(item);
    });
    usersBox.appendChild(fragment);
  }

  if (client) {
    client.auth.getUser().then(({ data }) => {
      if (data.user) onAuthenticated(data.user);
    });
  }
});
