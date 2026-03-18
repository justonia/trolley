package main

import (
	"fmt"
	"strings"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/lipgloss"
)

const maxHistory = 30

type keyEntry struct {
	display string
	detail  string
}

type model struct {
	width   int
	height  int
	lastKey string
	lastDet string
	history []keyEntry
}

func (m model) Init() tea.Cmd { return nil }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyPressMsg:
		if msg.String() == "ctrl+c" {
			return m, tea.Quit
		}

		display := msg.String()

		var parts []string
		parts = append(parts, fmt.Sprintf("code=%d", msg.Code))
		if msg.Text != "" {
			parts = append(parts, fmt.Sprintf("text=%q", msg.Text))
		}
		if msg.Mod != 0 {
			parts = append(parts, fmt.Sprintf("mod=%v", msg.Mod))
		}
		detail := strings.Join(parts, "  ")

		m.lastKey = display
		m.lastDet = detail
		m.history = append(m.history, keyEntry{display: display, detail: detail})
		if len(m.history) > maxHistory {
			m.history = m.history[len(m.history)-maxHistory:]
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	}
	return m, nil
}

func (m model) View() tea.View {
	if m.width == 0 {
		return tea.View{}
	}

	w := m.width

	headerStyle := lipgloss.NewStyle().
		Width(w - 2).
		Align(lipgloss.Center).
		Bold(true).
		Foreground(lipgloss.Color("#6BCF7F")).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("#6BCF7F")).
		Background(lipgloss.Color("#161B22"))

	lastKeyStyle := lipgloss.NewStyle().
		Width(w - 2).
		Padding(0, 1).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("#FFA657")).
		Background(lipgloss.Color("#161B22"))

	historyStyle := lipgloss.NewStyle().
		Width(w - 2).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("#79C0FF")).
		Background(lipgloss.Color("#161B22")).
		Padding(0, 1)

	footerStyle := lipgloss.NewStyle().
		Width(w - 2).
		Align(lipgloss.Center).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("#484F58")).
		Background(lipgloss.Color("#161B22")).
		Foreground(lipgloss.Color("#484F58"))

	labelStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("#FFA657"))

	detailStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#8B949E"))

	entryStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#C9D1D9"))

	// Header
	header := headerStyle.Render("Trolley Key Event Viewer (Bubble Tea)")

	// Last key
	lastDisplay := "(none)"
	lastDetail := ""
	if m.lastKey != "" {
		lastDisplay = m.lastKey
		lastDetail = m.lastDet
	}
	lastKey := lastKeyStyle.Render(
		labelStyle.Render("Last Key: "+lastDisplay) + "\n" +
			detailStyle.Render(lastDetail),
	)

	// History
	usedHeight := lipgloss.Height(header) + lipgloss.Height(lastKey) + 3 // footer
	historyHeight := m.height - usedHeight - 2                            // borders
	if historyHeight < 3 {
		historyHeight = 3
	}

	var lines []string
	start := 0
	visible := historyHeight - 2 // account for border
	if len(m.history) > visible {
		start = len(m.history) - visible
	}
	for _, e := range m.history[start:] {
		lines = append(lines, entryStyle.Render(e.display+"  "+e.detail))
	}
	historyContent := strings.Join(lines, "\n")
	history := historyStyle.Height(historyHeight).Render(historyContent)

	// Footer
	footer := footerStyle.Render("ctrl+c quit")

	content := lipgloss.JoinVertical(lipgloss.Left, header, lastKey, history, footer)
	v := tea.NewView(content)
	v.AltScreen = true
	return v
}

func main() {
	p := tea.NewProgram(model{})
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error: %v\n", err)
	}
}
