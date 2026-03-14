try {
  if (typeof CONFIG === 'undefined') {
    throw new Error("CONFIG is not defined.");
  }
  const { SUPABASE_URL, SUPABASE_ANON_KEY } = CONFIG;
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error("Supabase config is missing.");
  }
  client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
} catch (e) {
  console.error("Supabase Init Error:", e);
  configError = e.message;
}

let socket;
let myName = "";
let joined = false;

function isMe(username) {
  if (!username || !myName) return false;
  const match = String(username).trim().toLowerCase() === String(myName).trim().toLowerCase();
  console.log(`isMe check: msgUser="${username}", myName="${myName}", match=${match}`);
  return match;
}

document.addEventListener("DOMContentLoaded", () => {
  const authWrapper = document.getElementById("auth-container");
  const roomWrapper = document.getElementById("room-selection-container");
  const loginForm = document.getElementById("login-form");
  const signupForm = document.getElementById("signup-form");
  const showSignup = document.getElementById("show-signup");
  const showLogin = document.getElementById("show-login");
  const loginBtn = document.getElementById("login-button");
  const signupBtn = document.getElementById("signup-button");
  const clearChatBtn = document.getElementById("clear-chat-button");
  const logoutBtn = document.getElementById("logout-button");

  const mainChat = document.getElementById("main-chat");
  const msgBox = document.getElementById("chatInput");
  const msgArea = document.getElementById("chatMessages");
  const usersBox = document.getElementById("onlineUsers");
  const roomsBox = document.getElementById("userRoomsList");
  const displayName = document.getElementById("display-name");
  const sendBtn = document.getElementById("send-btn");
  const onlineCount = document.getElementById("online-count");

  const createRoomBtn = document.getElementById("show-create-room");
  const joinRoomBtn = document.getElementById("show-join-room");
  const createRoomSubmit = document.getElementById("create-room-submit");
  const joinRoomSubmit = document.getElementById("join-room-submit");
  const backToRoomsBtns = document.querySelectorAll(".back-to-rooms");
  const backToRoomsNav = document.getElementById("back-to-rooms-nav");
  const roomSelectionContainer = document.getElementById("room-selection-container");
  const roomsListView = document.getElementById("rooms-list-view");
  const createRoomView = document.getElementById("create-room-view");
  const joinRoomView = document.getElementById("join-room-view");
  const joinedRoomsList = document.getElementById("joined-rooms-list");

  const currentRoomDisplayName = document.getElementById("current-room-name");
  const sidebarAddRoomBtn = document.getElementById("sidebar-add-room-btn");
  const authBackToLoginBtn = document.getElementById("auth-back-to-login");

  const createRoomNameInput = document.getElementById("create-room-name");
  const createRoomIdInput = document.getElementById("create-room-id");
  const joinRoomNameInput = document.getElementById("join-room-name");
  const joinRoomIdInput = document.getElementById("join-room-id");

  authBackToLoginBtn.onclick = () => {
    roomSelectionContainer.style.display = "none";
    authWrapper.style.display = "flex";
    showLogin.click();
  };

  let currentRoom = null;
  let realtimeChannel = null;

  function showRoomList() {
    roomsListView.style.display = "flex";
    createRoomView.style.display = "none";
    joinRoomView.style.display = "none";

    createRoomNameInput.value = "";
    createRoomIdInput.value = "";
    joinRoomNameInput.value = "";
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

  backToRoomsBtns.forEach(btn => {
    btn.onclick = showRoomList;
  });

  backToRoomsNav.onclick = () => {
    mainChat.style.display = "none";
    roomSelectionContainer.style.display = "flex";

    if (socket && socket.readyState === 1) {
      socket.send(JSON.stringify({ type: "leave", user: myName, room: currentRoom ? currentRoom.id : "" }));
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
    roomSelectionContainer.style.display = "flex";
    showRoomList();
  };

  async function getJoinedRooms() {
    const { data: { user } } = await client.auth.getUser();
    const { data, error } = await client
      .from('user_rooms')
      .select('rooms(id, name, creator_id)')
      .eq('user_id', user.id);

    if (error) {
      console.error("Error fetching rooms:", error);
      return [];
    }
    return data.map(item => item.rooms);
  }

  async function saveJoinedRoom(id, name) {
    const { data: { user } } = await client.auth.getUser();

    const { data: roomExists } = await client
      .from('rooms')
      .select('id')
      .eq('id', id)
      .single();

    if (!roomExists) {
      await client.from('rooms').insert({ id, name, creator_id: user.id });
    }

    await client.from('user_rooms').upsert({ user_id: user.id, room_id: id });
  }

  async function renderJoinedRooms() {
    const rooms = await getJoinedRooms();
    const { data: { user } } = await client.auth.getUser();

    const activeId = currentRoom ? currentRoom.id : null;

    joinedRoomsList.innerHTML = "";
    if (rooms.length === 0) {
      joinedRoomsList.style.display = "none";
    } else {
      joinedRoomsList.style.display = "grid";
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
          delBtn.onclick = (e) => { e.stopPropagation(); deleteRoom(room.id); };
          actions.appendChild(delBtn);
        } else {
          const exitBtn = document.createElement("button");
          exitBtn.className = "btn-card-action exit";
          exitBtn.title = "Exit Room";
          exitBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4m7 14l5-5-5-5m5 5H9"/></svg>`;
          exitBtn.onclick = (e) => { e.stopPropagation(); exitRoom(room.id); };
          actions.appendChild(exitBtn);
        }

        card.appendChild(icon);
        card.appendChild(nameSpan);
        card.appendChild(actions);
        joinedRoomsList.appendChild(card);
      });
    }

    roomsBox.innerHTML = "";
    rooms.forEach(room => {
      const item = document.createElement("div");
      item.className = "room-item";
      if (room.id === activeId) item.classList.add("active");

      item.onclick = () => {
        if (activeId !== room.id) joinRoom(room.id, room.name);
      };

      item.innerHTML = `<span class="room-name">${room.name}</span>`;
      roomsBox.appendChild(item);
    });
  }

  async function deleteRoom(id) {
    if (!confirm("Are you sure you want to delete this room for everyone?")) return;
    try {
      const { error } = await client.from('rooms').delete().eq('id', id);
      if (error) {
        console.error("Delete Error:", error);
        return alert("Error deleting room. This might happen if you don't have permission or if the room is already gone.");
      }
      if (currentRoom && currentRoom.id === id) backToRoomsNav.click();
      renderJoinedRooms();
    } catch (err) {
      console.error("Delete Exception:", err);
      alert("An unexpected error occurred while deleting the room.");
    }
  }

  async function exitRoom(id) {
    if (!confirm("Remove this room from your list?")) return;
    const { data: { user } } = await client.auth.getUser();
    const { error } = await client.from('user_rooms').delete().eq('user_id', user.id).eq('room_id', id);
    if (error) return alert("Error exiting room: " + error.message);
    if (currentRoom && currentRoom.id === id) backToRoomsNav.click();
    renderJoinedRooms();
  }

  async function joinRoom(id, name) {
    if (!id || !name) return;

    const validRoomRegex = /^[a-zA-Z0-9]+$/;
    if (!validRoomRegex.test(id)) {
      return alert("Room ID can only contain letters and numbers.");
    }

    try {
      currentRoom = { id, name };
      await saveJoinedRoom(id, name);

      currentRoomDisplayName.textContent = `Room: ${name}`;
      roomSelectionContainer.style.display = "none";
      mainChat.style.display = "flex";
      joined = true;

      await renderJoinedRooms();
      await fetchHistory();
      connectWebSocket();
      setupRealtime();
    } catch (err) {
      console.error(err);
      alert("Error joining room.");
    }
  }

  async function handleCreateRoom() {
    const id = createRoomIdInput.value.trim();
    const name = createRoomNameInput.value.trim();
    if (!id || !name) return alert("Please enter both Room Name and Room ID.");

    const { data: existing } = await client.from('rooms').select('id').eq('id', id).maybeSingle();
    if (existing) return alert("A room with this ID already exists. Please choose a different ID.");

    joinRoom(id, name);
  }

  async function handleJoinRoom() {
    const id = joinRoomIdInput.value.trim();
    if (!id) return alert("Please enter the Room ID.");

    const { data: existing } = await client.from('rooms').select('id, name').eq('id', id).maybeSingle();
    if (!existing) return alert("Room does not exist. Please check the ID or create a new room.");

    joinRoom(id, existing.name);
  }

  createRoomSubmit.onclick = handleCreateRoom;
  joinRoomSubmit.onclick = handleJoinRoom;

  createRoomIdInput.addEventListener("keydown", e => { if (e.key === "Enter") createRoomSubmit.click(); });
  joinRoomIdInput.addEventListener("keydown", e => { if (e.key === "Enter") joinRoomSubmit.click(); });


  showSignup.onclick = (e) => {
    e.preventDefault();
    loginForm.style.display = "none";
    signupForm.style.display = "block";
  };

  showLogin.onclick = (e) => {
    e.preventDefault();
    signupForm.style.display = "none";
    loginForm.style.display = "block";
  };

  function setBtnLoading(btn, isLoading) {
    const text = btn.querySelector(".btn-text") || btn;
    const loader = btn.querySelector(".loader");
    if (isLoading) {
      if (loader) {
        text.style.display = "none";
        loader.style.display = "block";
      }
      btn.disabled = true;
    } else {
      if (loader) {
        text.style.display = "block";
        loader.style.display = "none";
      }
      btn.disabled = false;
    }
  }

  async function handleLogin() {
    const username = document.getElementById("login-username").value.trim();
    const password = document.getElementById("login-password").value;
    if (!username || !password) return alert("Please enter both username and password");

    if (!client) return alert(`Application configuration is missing!`);

    setBtnLoading(loginBtn, true);
    try {
      const { data, error } = await client.auth.signInWithPassword({
        email: `${username}@example.com`,
        password: password
      });

      if (error) {
        setBtnLoading(loginBtn, false);
        return alert(error.message);
      }
      onAuthenticated(data.user);
    } catch (err) {
      setBtnLoading(loginBtn, false);
      alert(err.message);
    }
  }

  async function handleSignup() {
    const username = document.getElementById("signup-username").value.trim();
    const password = document.getElementById("signup-password").value;
    if (!username || !password) return alert("Please enter both username and password");
    if (password.length < 6) return alert("Password must be at least 6 characters");

    if (!client) return alert("Application configuration is missing.");

    setBtnLoading(signupBtn, true);
    const { data, error } = await client.auth.signUp({
      email: `${username}@example.com`,
      password: password,
      options: { data: { username: username } }
    });

    setBtnLoading(signupBtn, false);
    if (error) return alert(error.message);

    alert("Account created successfully! You can now login.");
    showLogin.click();
  }

  async function handleLogout() {
    if (confirm("Are you sure you want to logout?")) {
      await client.auth.signOut();
      location.reload();
    }
  }

  async function handleClearChat() {
    if (!currentRoom) return;
    if (confirm("Clear room history for you? This will sync across your devices.")) {
      const { data: { user } } = await client.auth.getUser();
      const { error } = await client
        .from('user_room_clears')
        .upsert({ user_id: user.id, room_id: currentRoom.id, cleared_at: new Date().toISOString() });

      if (error) {
        console.error("Clear Chat Error:", error);
        return alert("Failed to clear chat. This might be a permission issue. Please ensure RLS policies are correct.");
      }
      msgArea.innerHTML = "";
    }
  }

  loginBtn.onclick = handleLogin;
  signupBtn.onclick = handleSignup;
  clearChatBtn.onclick = handleClearChat;
  logoutBtn.onclick = handleLogout;

  document.getElementById("login-username").addEventListener("keydown", (e) => {
    if (e.key === "Enter") handleLogin();
  });
  document.getElementById("login-password").addEventListener("keydown", (e) => {
    if (e.key === "Enter") handleLogin();
  });


  async function onAuthenticated(user) {
    myName = (user.user_metadata?.username || user.email.split('@')[0] || "Unknown").trim();
    console.log("Authenticated as:", myName, "Full Metadata:", user.user_metadata);
    displayName.textContent = myName;
    authWrapper.style.display = "none";
    roomSelectionContainer.style.display = "flex";
    showRoomList();
    renderJoinedRooms();
  }

  async function fetchHistory() {
    if (!currentRoom) return;

    const { data: { user } } = await client.auth.getUser();

    const { data: clearData, error: clearError } = await client
      .from('user_room_clears')
      .select('cleared_at')
      .eq('user_id', user.id)
      .eq('room_id', currentRoom.id)
      .maybeSingle();

    if (clearError && clearError.code !== 'PGRST116') console.warn("Notice: Error fetching clear-at record:", clearError);
    const clearedAt = (clearData && clearData.cleared_at) ? clearData.cleared_at : '1970-01-01T00:00:00Z';

    const { data: deletedData } = await client
      .from('user_deleted_messages')
      .select('message_id')
      .eq('user_id', user.id);

    const deletedIDs = deletedData ? deletedData.map(d => d.message_id) : [];

    const { data, error } = await client
      .from('messages')
      .select('*')
      .eq('room_id', currentRoom.id)
      .gt('created_at', clearedAt)
      .order('created_at', { ascending: true })
      .limit(100);

    if (error) throw error;

    if (data) {
      msgArea.innerHTML = "";
      const frag = document.createDocumentFragment();
      data.forEach(m => {
        if (!deletedIDs.includes(m.id)) {
          const d = createMsgElement(m.username, m.text, m.created_at, m.id);
          frag.appendChild(d);
        }
      });
      msgArea.appendChild(frag);
      msgArea.scrollTop = msgArea.scrollHeight;
    }
  }

  function setupRealtime() {
    if (realtimeChannel) {
      realtimeChannel.unsubscribe();
    }

    realtimeChannel = client.channel(`public:messages:room:${currentRoom.id}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'messages',
        filter: `room_id=eq.${currentRoom.id}`
      }, payload => {
        if (!isMe(payload.new.username)) {
          addMsg(payload.new.username, payload.new.text, payload.new.created_at, payload.new.id);
        }
      })
      .on('postgres_changes', {
        event: 'DELETE',
        schema: 'public',
        table: 'messages'
      }, payload => {
        const el = document.querySelector(`[data-id="${payload.old.id}"]`);
        if (el) el.remove();
      })
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'user_deleted_messages'
      }, payload => {
        client.auth.getUser().then(({ data }) => {
          if (data && data.user && payload.new.user_id === data.user.id) {
            const el = document.querySelector(`[data-id="${payload.new.message_id}"]`);
            if (el) el.remove();
          }
        });
      })
      .on('postgres_changes', {
        event: 'UPSERT',
        schema: 'public',
        table: 'user_room_clears'
      }, payload => {
        if (payload.new.room_id === currentRoom.id) {
          msgArea.innerHTML = "";
        }
      })
      .subscribe();
  }

  function connectWebSocket() {
    if (socket && socket.readyState !== WebSocket.CLOSED) {
      socket.close();
    }

    const proto = location.protocol === "https:" ? "wss" : "ws";
    const host = location.host;
    socket = new WebSocket(`${proto}://${host}/ws`);

    socket.onopen = () => {
      if (myName && joined && currentRoom) {
        socket.send(JSON.stringify({ type: "join", user: myName, room: currentRoom.id }));
      }
    };

    socket.onmessage = e => {
      const data = JSON.parse(e.data);

      if (data.room && data.room !== currentRoom.id) return;

      if (data.type === "users") {
        showUsers(data.users);
        onlineCount.textContent = `${data.users.length} online`;
      } else if (data.type === "message") {
        if (data.user !== myName && data.room === currentRoom.id) {
          addMsg(data.user, data.text, new Date().toISOString());
        }
      }
    };

    socket.onclose = () => {
      if (joined && currentRoom) {
        setTimeout(connectWebSocket, 3000);
      }
    };
  }

  async function sendMessage() {
    const text = msgBox.value.trim();
    if (!text || !joined || !currentRoom) return;

    try {
      console.log("Inserting message to Supabase. myName:", myName, "text:", text);
      const { error } = await client.from('messages').insert({
        username: myName,
        text: text,
        room_id: currentRoom.id
      });

      if (error) {
        console.error("Save Error:", error);
        alert("Error saving message to database. It might not persist if you leave the room.");
      }

      addMsg(myName, text, new Date().toISOString());
      msgBox.value = "";

      if (socket && socket.readyState === 1) {

        socket.send(JSON.stringify({ type: "message", user: myName, text: text, room: currentRoom.id }));
      }
    } catch (e) {
      console.error(e);
    }
  }

  sendBtn.onclick = sendMessage;
  msgBox.onkeydown = e => { if (e.key === "Enter") sendMessage(); };

  function createMsgElement(user, text, timestamp, id) {
    const d = document.createElement("div");
    const sameUser = isMe(user);
    console.log(`createMsgElement: user="${user}", myName="${myName}", sameUser=${sameUser}`);
    d.className = sameUser ? "msg me" : "msg other";
    if (id) d.setAttribute("data-id", id);

    const nameSpan = document.createElement("span");
    nameSpan.className = "name";
    nameSpan.textContent = sameUser ? "You" : (user || "Anonymous User");
    if (!user && !sameUser) {
        console.warn("Message has no username attached!");
    }

    const timeSpan = document.createElement("span");
    timeSpan.className = "time";
    if (timestamp) {
      const date = new Date(timestamp);
      timeSpan.textContent = date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    }

    const contentSpan = document.createElement("span");
    contentSpan.className = "msg-content";
    contentSpan.textContent = text;

    d.appendChild(nameSpan);
    d.appendChild(contentSpan);
    d.appendChild(timeSpan);

    const actions = document.createElement("div");
    actions.className = "msg-actions";
    
    // Delete for Me (Always available)
    const delMeBtn = document.createElement("button");
    delMeBtn.className = "btn-delete me-only";
    delMeBtn.title = "Delete for Me";
    delMeBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg><span class="label">For Me</span>`;
    delMeBtn.onclick = () => deleteMessageForMe(id, d);
    actions.appendChild(delMeBtn);

    // Delete for Everyone (Only for sender)
    if (sameUser) {
      const delAllBtn = document.createElement("button");
      delAllBtn.className = "btn-delete all";
      delAllBtn.title = "Delete for Everyone";
      delAllBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg><span class="label">For All</span>`;
      delAllBtn.onclick = () => deleteMessageForEveryone(id);
      actions.appendChild(delAllBtn);
    }

    d.appendChild(actions);

    return d;
  }

  async function deleteMessageForEveryone(msgId) {
    if (!msgId) return;
    if (!confirm("Delete this message for everyone?")) return;
    const { error } = await client
      .from('messages')
      .delete()
      .eq('id', msgId);

    if (error) return alert("Error deleting message for everyone: " + error.message);
    // Realtime will handle removal
  }

  async function deleteMessageForMe(msgId, element) {
    if (!msgId) return;
    const { data: { user } } = await client.auth.getUser();
    const { error } = await client
      .from('user_deleted_messages')
      .insert({ user_id: user.id, message_id: msgId });

    if (error) return alert("Error deleting message: " + error.message);
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

    const d = createMsgElement(user, text, timestamp, id);
    msgArea.appendChild(d);
    msgArea.scrollTop = msgArea.scrollHeight;
  }

  function showUsers(list) {
    usersBox.innerHTML = "";
    const frag = document.createDocumentFragment();
    list.forEach(name => {
      const item = document.createElement("div");
      item.className = "user-item";
      item.innerHTML = `<div class="user-avatar">${name.charAt(0).toUpperCase()}</div><span>${name}</span>`;
      frag.appendChild(item);
    });
    usersBox.appendChild(frag);
  }

  if (client) {
    client.auth.getUser().then(({ data }) => {
      if (data.user) onAuthenticated(data.user);
    });
  }
});
