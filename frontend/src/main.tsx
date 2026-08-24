import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'

const savedTheme = localStorage.getItem('sa_theme')
if (savedTheme === 'dark' || savedTheme === 'light') document.documentElement.setAttribute('data-theme', savedTheme)

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)

