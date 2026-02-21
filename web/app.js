const SUPABASE_URL = 'https://mjszmayetfrhqzmxsdzd.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_eM10rdD5pxCi0NrbRvZpZQ_QCx2K3K-';
const client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

let socket;
let myName = "";
let joined = false;

document.addEventListener("DOMContentLoaded", () => {
  const authContainer = document.getElementById("auth-container");
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
  async function handleLogin() {
    const username = document.getElementById("login-username").value.trim();
    const password = document.getElementById("login-password").value;
    if (!username || !password) return alert("Please enter credentials");

    const { data, error } = await client.auth.signInWithPassword({
      email: `${username}@example.com`,
      password: password
    });

    if (error) return alert(error.message);
    onAuthenticated(data.user);
  }

  async function handleSignup() {
    const username = document.getElementById("signup-username").value.trim();
    const password = document.getElementById("signup-password").value;
    if (!username || !password) return alert("Please enter credentials");

    const { data, error } = await client.auth.signUp({
      email: `${username}@example.com`,
      password: password,
      options: { data: { username: username } }
    });

    if (error) return alert(error.message);
    alert("Account created! Please login.");
    showLogin.click();
  }

  async function handleLogout() {
    await client.auth.signOut();
    location.reload();
  }

  loginBtn.onclick = handleLogin;
  signupBtn.onclick = handleSignup;
  logoutBtn.onclick = handleLogout;

  async function onAuthenticated(user) {
    myName = user.user_metadata.username || user.email.split('@')[0];
    displayName.textContent = `Hello, ${myName}`;
    authContainer.style.display = "none";
    mainChat.style.display = "block";
    joined = true;

    await fetchHistory();
    connectWebSocket();
    setupRealtime();
  }

  async function fetchHistory() {
    const { data, error } = await client
      .from('messages')
      .select('*')
      .order('created_at', { ascending: true })
      .limit(100);

    if (data) {
      msgArea.innerHTML = "";
      data.forEach(m => addMsg(m.username, m.text));
    }
  }

  function setupRealtime() {
    client.channel('public:messages')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, payload => {
        if (payload.new.username !== myName) {
          addMsg(payload.new.username, payload.new.text);
        }
      })
      .subscribe();
  }

  function connectWebSocket() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    const host = location.host.includes("localhost") || location.host.includes("127.0.0.1") ? location.host : location.host;
    socket = new WebSocket(`${proto}://${host}/ws`);

    socket.onopen = () => {
      if (myName && joined) {
        socket.send(JSON.stringify({ type: "join", user: myName }));
      }
    };

    socket.onmessage = e => {
      const data = JSON.parse(e.data);
      if (data.type === "users") showUsers(data.users);

    };

    socket.onclose = () => setTimeout(connectWebSocket, 2000);
  }

  msgBox.addEventListener("keydown", async e => {
    if (!joined) return;
    if (e.key === "Enter") {
      const text = msgBox.value.trim();
      if (!text) return;

      await client.from('messages').insert({ username: myName, text: text });

      addMsg(myName, text);


      if (socket && socket.readyState === 1) {
        socket.send(JSON.stringify({ type: "message", user: myName, text }));
      }

      msgBox.value = "";
    }
  });

  function addMsg(user, text) {

    const d = document.createElement("div");
    d.className = user === myName ? "msg me" : "msg other";
    d.innerHTML = `<span class="name">${user}</span>${text}`;
    msgArea.appendChild(d);
    msgArea.scrollTop = msgArea.scrollHeight;
  }

  function showUsers(list) {
    usersBox.innerHTML = "";
    list.forEach(name => {
      const d = document.createElement("div");
      d.textContent = name;
      usersBox.appendChild(d);
    });
  }

  client.auth.getUser().then(({ data }) => {
    if (data.user) onAuthenticated(data.user);
  });
});
