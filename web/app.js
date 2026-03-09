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
  const createRoomIdInput = document.getElementById("create-room-id");
  const joinRoomIdInput = document.getElementById("join-room-id");
  const currentRoomName = document.getElementById("current-room-name");

  let currentRoom = null;
  let realtimeChannel = null;

  // --- UI Toggles for Room Views ---
  function showRoomList() {
    roomsListView.style.display = "flex";
    createRoomView.style.display = "none";
    joinRoomView.style.display = "none";
    
    // Clear inputs
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

  backToRoomsBtns.forEach(btn => {
    btn.onclick = showRoomList;
  });

  backToRoomsNav.onclick = () => {
    mainChat.style.display = "none";
    roomSelectionContainer.style.display = "flex";
    
    // Cleanup chat state
    if (socket && socket.readyState === 1) {
      socket.send(JSON.stringify({ type: "leave", user: myName, room: currentRoom }));
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

  // --- LocalStorage for Joined Rooms ---
  function getJoinedRooms() {
    const saved = localStorage.getItem("realTalk_joinedRooms");
    return saved ? JSON.parse(saved) : [];
  }

  function saveJoinedRoom(roomId) {
    let rooms = getJoinedRooms();
    if (!rooms.includes(roomId)) {
      rooms.push(roomId);
      localStorage.setItem("realTalk_joinedRooms", JSON.stringify(rooms));
    }
  }

  function renderJoinedRooms() {
    const rooms = getJoinedRooms();
    joinedRoomsList.innerHTML = "";
    
    if (rooms.length === 0) {
      joinedRoomsList.style.display = "none";
    } else {
      joinedRoomsList.style.display = "grid";
      const frag = document.createDocumentFragment();
      rooms.forEach(roomId => {
        const card = document.createElement("div");
        card.className = "room-card";
        card.onclick = () => joinRoom(roomId);
        
        const icon = document.createElement("div");
        icon.innerHTML = `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--primary)" stroke-width="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M23 21v-2a4 4 0 0 0-3-3.87"></path><path d="M16 3.13a4 4 0 0 1 0 7.75"></path></svg>`;
        
        const nameSpan = document.createElement("span");
        nameSpan.textContent = roomId;
        
        card.appendChild(icon);
        card.appendChild(nameSpan);
        frag.appendChild(card);
      });
      joinedRoomsList.appendChild(frag);
    }
  }

  async function joinRoom(roomId) {
    if (!roomId) return;
    
    // validate alphanumeric using regex
    const validRoomRegex = /^[a-zA-Z0-9]+$/;
    if (!validRoomRegex.test(roomId)) {
      return alert("Room ID can only contain letters and numbers.");
    }

    currentRoom = roomId;
    saveJoinedRoom(roomId);
    
    currentRoomName.textContent = `Room: ${roomId}`;
    roomSelectionContainer.style.display = "none";
    mainChat.style.display = "flex";
    joined = true;

    try {
      await fetchHistory();
      connectWebSocket();
      setupRealtime();
    } catch (err) {
      console.error(err);
      alert("Error loading chat data.");
    }
  }

  createRoomSubmit.onclick = () => joinRoom(createRoomIdInput.value.trim());
  joinRoomSubmit.onclick = () => joinRoom(joinRoomIdInput.value.trim());

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

  document.getElementById("login-username").addEventListener("keydown", (e) => {
    if (e.key === "Enter") handleLogin();
  });
  document.getElementById("login-password").addEventListener("keydown", (e) => {
    if (e.key === "Enter") handleLogin();
  });

  function showRoomInput(title) {
    roomActionsInitial.style.display = "none";
    roomActionsInput.style.display = "flex";
    roomActionTitle.textContent = title;
    actionRoomIdInput.value = "";
    actionRoomIdInput.focus();
  }

  function showRoomInitial() {
    roomActionsInitial.style.display = "flex";
    roomActionsInput.style.display = "none";
  }

  showCreateRoomBtn.onclick = () => showRoomInput("Enter Room ID to Create");
  showJoinRoomBtn.onclick = () => showRoomInput("Enter Room ID to Join");
  backToRoomActionsBtn.onclick = () => showRoomInitial();

  confirmRoomBtn.onclick = () => {
    const id = actionRoomIdInput.value.trim().toUpperCase();
    if (!id) return alert("Please enter a Room ID");
    enterRoom(id);
  };

  actionRoomIdInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") confirmRoomBtn.click();
  });

  sidebarAddRoomBtn.onclick = () => {
    mainChat.style.display = "none";
    roomWrapper.style.display = "flex";
    showRoomInitial();
  };

  async function onAuthenticated(user) {
    myName = user.user_metadata.username || user.email.split('@')[0];
    displayName.textContent = myName;
    authWrapper.style.display = "none";
    
    // Show room selection instead of main chat
    roomSelectionContainer.style.display = "flex";
    showRoomList();
  }

  async function fetchHistory() {
    if (!currentRoom) return;
    
    const { data, error } = await client
      .from('messages')
      .select('*')
      .eq('room_id', currentRoom)
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
    
    realtimeChannel = client.channel(`public:messages:room:${currentRoom}`)
      .on('postgres_changes', { 
        event: 'INSERT', 
        schema: 'public', 
        table: 'messages',
        filter: `room_id=eq.${currentRoom}`
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
    if (socket && socket.readyState !== WebSocket.CLOSED) {
      socket.close();
    }
    
    const proto = location.protocol === "https:" ? "wss" : "ws";
    const host = location.host;
    socket = new WebSocket(`${proto}://${host}/ws`);

    socket.onopen = () => {
      if (myName && joined && currentRoom) {
        socket.send(JSON.stringify({ type: "join", user: myName, room: currentRoom }));
      }
    };

    socket.onmessage = e => {
      const data = JSON.parse(e.data);
      
      // Ensure we only process messages for current room
      if (data.room && data.room !== currentRoom) return;
      
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
      if (joined && currentRoom) {
        setTimeout(connectWebSocket, 3000);
      }
    };
  }

  async function sendMessage() {
    const text = msgBox.value.trim();
    if (!text || !joined || !currentRoom) return;

    try {
      await client.from('messages').insert({ 
        username: myName, 
        text: text,
        room_id: currentRoom 
      });
      
      addMsg(myName, text, new Date().toISOString());
      msgBox.value = "";

      if (socket && socket.readyState === 1) {
        socket.send(JSON.stringify({ type: "message", user: myName, text: text, room: currentRoom }));
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
