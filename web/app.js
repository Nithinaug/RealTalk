let client;
let configError = null;

try {
  if (typeof CONFIG === 'undefined') {
    throw new Error("CONFIG is not defined. config.js may have failed to load.");
  }

  const SUPABASE_URL = CONFIG.SUPABASE_URL;
  const SUPABASE_ANON_KEY = CONFIG.SUPABASE_ANON_KEY;

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error("Supabase URL or Anon Key is empty in CONFIG.");
  }

  client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
} catch (e) {
  configError = e.message;
}

let socket;
let myName = "";
let currentRoomID = "";
let joined = false;

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
  const displayRoomID = document.getElementById("display-room-id");
  const sendBtn = document.getElementById("send-btn");
  const onlineCount = document.getElementById("online-count");

  const createRoomBtn = document.getElementById("create-room-btn");
  const joinRoomBtn = document.getElementById("join-room-btn");
  const joinRoomInput = document.getElementById("join-room-id");

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
    if (!currentRoomID) return;
    if (confirm("Clear room history for you? This will sync across your devices.")) {
      const { data: { user } } = await client.auth.getUser();
      const { error } = await client
        .from('user_room_clears')
        .upsert({ user_id: user.id, room_id: currentRoomID, cleared_at: new Date().toISOString() });

      if (error) return alert("Error: " + error.message);
      msgArea.innerHTML = "";
    }
  }

  loginBtn.onclick = handleLogin;
  signupBtn.onclick = handleSignup;
  clearChatBtn.onclick = handleClearChat;
  logoutBtn.onclick = handleLogout;

  joinRoomBtn.onclick = () => {
    const id = joinRoomInput.value.trim().toUpperCase();
    if (!id) return alert("Please enter a Room ID");
    enterRoom(id);
  };

  async function onAuthenticated(user) {
    myName = user.user_metadata.username || user.email.split('@')[0];
    displayName.textContent = myName;
    authWrapper.style.display = "none";
    roomWrapper.style.display = "flex";
    loadUserRooms();
  }

  function loadUserRooms() {
    const rooms = JSON.parse(localStorage.getItem(`rooms_${myName}`) || "[]");
    renderRoomsList(rooms);
  }

  function renderRoomsList(rooms) {
    roomsBox.innerHTML = "";
    rooms.forEach(id => {
      const div = document.createElement("div");
      div.className = id === currentRoomID ? "room-item active" : "room-item";
      div.innerHTML = `<span class="room-name">Room ${id}</span><span class="room-id">#${id}</span>`;
      div.onclick = () => enterRoom(id);
      roomsBox.appendChild(div);
    });
  }

  async function enterRoom(roomID) {
    currentRoomID = roomID;
    displayRoomID.textContent = "#" + roomID;
    roomWrapper.style.display = "none";
    mainChat.style.display = "flex";
    joined = true;

    const rooms = JSON.parse(localStorage.getItem(`rooms_${myName}`) || "[]");
    if (!rooms.includes(roomID)) {
      rooms.push(roomID);
      localStorage.setItem(`rooms_${myName}`, JSON.stringify(rooms));
    }
    renderRoomsList(rooms);

    try {
      if (socket) socket.close();
      await fetchHistory();
      connectWebSocket();
      setupRealtime();
    } catch (err) {
      console.error(err);
      alert("Error loading room data.");
    }
  }

  async function fetchHistory() {
    const { data: { user } } = await client.auth.getUser();

    const { data: clearData } = await client
      .from('user_room_clears')
      .select('cleared_at')
      .eq('user_id', user.id)
      .eq('room_id', currentRoomID)
      .single();

    const clearedAt = clearData ? clearData.cleared_at : '1970-01-01T00:00:00Z';

    const { data: deletedData } = await client
      .from('user_deleted_messages')
      .select('message_id')
      .eq('user_id', user.id);

    const deletedIDs = deletedData ? deletedData.map(d => d.message_id) : [];

    const { data, error } = await client
      .from('messages')
      .select('*')
      .eq('room_id', currentRoomID)
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
    client.channel(`room:${currentRoomID}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'messages',
        filter: `room_id=eq.${currentRoomID}`
      }, payload => {
        if (payload.new.username !== myName) {
          addMsg(payload.new.username, payload.new.text, payload.new.created_at, payload.new.id);
        }
      })
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'user_deleted_messages'
      }, payload => {
        const el = document.querySelector(`[data-id="${payload.new.message_id}"]`);
        if (el) el.remove();
      })
      .on('postgres_changes', {
        event: 'UPSERT',
        schema: 'public',
        table: 'user_room_clears'
      }, payload => {
        if (payload.new.room_id === currentRoomID) {
          msgArea.innerHTML = "";
        }
      })
      .subscribe();
  }

  function connectWebSocket() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    const host = location.host;
    socket = new WebSocket(`${proto}://${host}/ws`);

    socket.onopen = () => {
      if (myName && joined && currentRoomID) {
        socket.send(JSON.stringify({ type: "join", user: myName, room_id: currentRoomID }));
      }
    };

    socket.onmessage = e => {
      const data = JSON.parse(e.data);
      if (data.type === "users") {
        showUsers(data.users);
        onlineCount.textContent = `${data.users.length} online`;
      } else if (data.type === "message") {
        if (data.user !== myName && data.room_id === currentRoomID) {
          addMsg(data.user, data.text, new Date().toISOString());
        }
      }
    };

    socket.onclose = () => {
      if (joined) {
        setTimeout(connectWebSocket, 3000);
      }
    };
  }

  async function sendMessage() {
    const text = msgBox.value.trim();
    if (!text || !joined || !currentRoomID) return;

    try {
      const { data, error } = await client.from('messages').insert({
        username: myName,
        text: text,
        room_id: currentRoomID
      }).select().single();

      if (error) throw error;

      addMsg(myName, text, new Date().toISOString(), data.id);
      msgBox.value = "";

      if (socket && socket.readyState === 1) {
        socket.send(JSON.stringify({ type: "message", user: myName, text, room_id: currentRoomID }));
      }
    } catch (e) {
      console.error(e);
    }
  }

  sendBtn.onclick = sendMessage;
  msgBox.onkeydown = e => { if (e.key === "Enter") sendMessage(); };

  function createMsgElement(user, text, timestamp, id) {
    const d = document.createElement("div");
    d.className = user === myName ? "msg me" : "msg other";
    if (id) d.setAttribute("data-id", id);

    const nameSpan = document.createElement("span");
    nameSpan.className = "name";
    nameSpan.textContent = user;

    const timeSpan = document.createElement("span");
    timeSpan.className = "time";
    if (timestamp) {
      const date = new Date(timestamp);
      timeSpan.textContent = date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    }

    const textNode = document.createTextNode(text);

    d.appendChild(nameSpan);
    d.appendChild(textNode);
    d.appendChild(timeSpan);

    const actions = document.createElement("div");
    actions.className = "msg-actions";
    const delBtn = document.createElement("button");
    delBtn.className = "btn-delete";
    delBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>`;
    delBtn.onclick = () => deleteMessageForMe(id, d);
    actions.appendChild(delBtn);
    d.appendChild(actions);

    return d;
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
