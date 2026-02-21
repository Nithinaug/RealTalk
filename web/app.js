let client;
try {
  const SUPABASE_URL = CONFIG.SUPABASE_URL;
  const SUPABASE_ANON_KEY = CONFIG.SUPABASE_ANON_KEY;
  client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  console.log("Supabase client initialized.");
} catch (e) {
  console.error("Failed to initialize Supabase client. This usually means config.js failed to load.", e);
}

let socket;
let myName = "";
let joined = false;

document.addEventListener("DOMContentLoaded", () => {
  const authWrapper = document.getElementById("auth-container");
  const loginForm = document.getElementById("login-form");
  const signupForm = document.getElementById("signup-form");
  const showSignup = document.getElementById("show-signup");
  const showLogin = document.getElementById("show-login");
  const loginBtn = document.getElementById("login-button");
  const signupBtn = document.getElementById("signup-button");
  const logoutBtn = document.getElementById("logout-button");

  const mainChat = document.getElementById("main-chat");
  const msgBox = document.getElementById("chatInput");
  const msgArea = document.getElementById("chatMessages");
  const usersBox = document.getElementById("onlineUsers");
  const displayName = document.getElementById("display-name");
  const sendBtn = document.getElementById("send-btn");
  const onlineCount = document.getElementById("online-count");

  showSignup.onclick = (e) => {
    e.preventDefault();
    console.log("Switching to signup form");
    loginForm.style.display = "none";
    signupForm.style.display = "block";
  };

  showLogin.onclick = (e) => {
    e.preventDefault();
    console.log("Switching to login form");
    signupForm.style.display = "none";
    loginForm.style.display = "block";
  };

  function setBtnLoading(btn, isLoading) {
    const text = btn.querySelector(".btn-text");
    const loader = btn.querySelector(".loader");
    if (isLoading) {
      text.style.display = "none";
      loader.style.display = "block";
      btn.disabled = true;
    } else {
      text.style.display = "block";
      loader.style.display = "none";
      btn.disabled = false;
    }
  }

  async function handleLogin() {
    console.log("Starting handleLogin...");
    const username = document.getElementById("login-username").value.trim();
    const password = document.getElementById("login-password").value;
    if (!username || !password) return alert("Please enter both username and password");

    if (!client) {
      return alert("Application configuration is missing. Please refresh the page or check the server logs.");
    }

    // Check if user is already online (from the onlineUsers list)
    const onlineUsersList = Array.from(document.querySelectorAll(".user-item span")).map(el => el.textContent);
    if (onlineUsersList.includes(username)) {
      if (!confirm(`Warning: User "${username}" appears to be already logged in on another device. Continue?`)) {
        return;
      }
    }

    setBtnLoading(loginBtn, true);
    try {
      console.log(`Attempting login for: ${username}@example.com`);
      const { data, error } = await client.auth.signInWithPassword({
        email: `${username}@example.com`,
        password: password
      });

      if (error) {
        console.error("Auth error:", error);
        setBtnLoading(loginBtn, false);
        return alert(error.message);
      }
      console.log("Auth success, user data:", data.user);
      onAuthenticated(data.user);
    } catch (err) {
      console.error("Unexpected error during login:", err);
      setBtnLoading(loginBtn, false);
      alert("An unexpected error occurred: " + err.message);
    }
  }

  async function handleSignup() {
    const username = document.getElementById("signup-username").value.trim();
    const password = document.getElementById("signup-password").value;
    if (!username || !password) return alert("Please enter both username and password");
    if (password.length < 6) return alert("Password must be at least 6 characters");

    if (!client) {
      return alert("Application configuration is missing. Please refresh the page or check the server logs.");
    }

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

  loginBtn.onclick = handleLogin;
  signupBtn.onclick = handleSignup;
  logoutBtn.onclick = handleLogout;

  async function onAuthenticated(user) {
    console.log("onAuthenticated called for:", user.email);
    myName = user.user_metadata.username || user.email.split('@')[0];
    displayName.textContent = myName;
    authWrapper.style.display = "none";
    mainChat.style.display = "flex";
    joined = true;

    try {
      console.log("Fetching chat history...");
      await fetchHistory();
      console.log("Connecting WebSocket...");
      connectWebSocket();
      console.log("Setting up Realtime...");
      setupRealtime();
    } catch (err) {
      console.error("Error during post-auth setup:", err);
      alert("Error loading chat data. Check console for details.");
    }
  }

  async function fetchHistory() {
    const { data, error } = await client
      .from('messages')
      .select('*')
      .order('created_at', { ascending: true })
      .limit(100);

    if (error) {
      console.error("Error fetching history:", error);
      throw error;
    }

    if (data) {
      console.log(`Fetched ${data.length} messages.`);
      msgArea.innerHTML = "";
      data.forEach(m => addMsg(m.username, m.text, m.created_at));
    }
  }

  function setupRealtime() {
    client.channel('public:messages')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, payload => {
        if (payload.new.username !== myName) {
          addMsg(payload.new.username, payload.new.text, payload.new.created_at);
        }
      })
      .subscribe();
  }

  function connectWebSocket() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    const host = location.host;
    socket = new WebSocket(`${proto}://${host}/ws`);

    socket.onopen = () => {
      if (myName && joined) {
        socket.send(JSON.stringify({ type: "join", user: myName }));
      }
    };

    socket.onmessage = e => {
      const data = JSON.parse(e.data);
      if (data.type === "users") {
        showUsers(data.users);
        onlineCount.textContent = `${data.users.length} online`;
      }
    };

    socket.onclose = () => setTimeout(connectWebSocket, 3000);
  }

  async function sendMessage() {
    const text = msgBox.value.trim();
    if (!text || !joined) return;

    try {
      await client.from('messages').insert({ username: myName, text: text });
      addMsg(myName, text, new Date().toISOString());
      msgBox.value = "";

      if (socket && socket.readyState === 1) {
        socket.send(JSON.stringify({ type: "message", user: myName, text }));
      }
    } catch (e) {
      console.error(e);
    }
  }

  sendBtn.onclick = sendMessage;
  msgBox.addEventListener("keydown", e => {
    if (e.key === "Enter") sendMessage();
  });

  function addMsg(user, text, timestamp) {
    const d = document.createElement("div");
    d.className = user === myName ? "msg me" : "msg other";

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

    msgArea.appendChild(d);
    msgArea.scrollTop = msgArea.scrollHeight;
  }

  function showUsers(list) {
    usersBox.innerHTML = "";
    list.forEach(name => {
      const item = document.createElement("div");
      item.className = "user-item";

      const avatar = document.createElement("div");
      avatar.className = "user-avatar";
      avatar.textContent = name.charAt(0).toUpperCase();

      const nameEl = document.createElement("span");
      nameEl.textContent = name;

      item.appendChild(avatar);
      item.appendChild(nameEl);
      usersBox.appendChild(item);
    });
  }

  client.auth.getUser().then(({ data }) => {
    if (data.user) onAuthenticated(data.user);
  });
});
